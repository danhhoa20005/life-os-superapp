import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/services/native_voice_assistant_bridge.dart';
import '../../../../core/utils/omni_action_executor.dart';
import '../../../../core/utils/smart_omni_intent_parser.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/utils/voice_utterance_completeness.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../calendar/presentation/bloc/calendar_bloc.dart';
import '../../../daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../domain/entities/financial_ai_entities.dart';
import '../../domain/entities/gemini_copilot_entities.dart';
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

/// Phase 16.1, 16.2 & Gemini Hybrid Copilot — Offline Financial AI + Opt-in Gemini Multi-Domain Assistant.
class FinancialAiAssistantPage extends StatelessWidget {
  final String? initialText;
  final FinancialInputSource initialSource;

  const FinancialAiAssistantPage({
    super.key,
    this.initialText,
    this.initialSource = FinancialInputSource.manualText,
  });

  @override
  Widget build(BuildContext context) {
    return EnsureGeminiCopilotScope(
      child: _FinancialAiAssistantBody(
        initialText: initialText,
        initialSource: initialSource,
      ),
    );
  }
}

class _FinancialAiAssistantBody extends StatefulWidget {
  final String? initialText;
  final FinancialInputSource initialSource;

  const _FinancialAiAssistantBody({
    this.initialText,
    this.initialSource = FinancialInputSource.manualText,
  });

  @override
  State<_FinancialAiAssistantBody> createState() =>
      _FinancialAiAssistantBodyState();
}

class _FinancialAiAssistantBodyState extends State<_FinancialAiAssistantBody> {
  late final TextEditingController _inputCtrl;
  StreamSubscription<VoiceAssistantSignal>? _voiceSub;
  Timer? _autoEndpointTimer;
  bool _isListening = false;
  String? _voiceHint;
  FinancialInputSource _activeSource = FinancialInputSource.manualText;

  static const List<(String label, String sample)> _samplePrompts = [
    (
      'Đa tác vụ Gemini',
      'Sáng ăn phở 55k, chiều mai 15h họp dự án và nhắc mua sữa tươi',
    ),
    (
      'Đa khoản thu chi',
      'Chiều qua tôi đổ xăng 70k và mua nước 15 nghìn',
    ),
    (
      '3 khoản giọng nói',
      'Trưa nay tôi ăn cơm hết 45 nghìn, đi taxi mất 80 nghìn và được thưởng 500 nghìn',
    ),
    (
      'Chuyển nội bộ',
      'Chuyển 2 triệu từ MB sang Vietcombank của tôi',
    ),
    (
      'Rút tiền ATM',
      'Rút 1 triệu từ ATM',
    ),
    (
      'Nhận lương',
      'Nhận lương 12tr',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _activeSource = widget.initialSource;
    _inputCtrl = TextEditingController(text: widget.initialText ?? '');

    final bridge = sl<NativeVoiceAssistantBridge>();
    _voiceSub = bridge.watchSignals().listen((sig) {
      if (!mounted) return;
      switch (sig) {
        case VoiceStateSignal(:final status):
          setState(() {
            _isListening = status == 'listening';
            if (_isListening) {
              _voiceHint =
                  'Đang tự động thu âm — nói xong hệ thống sẽ tự dừng để bạn xác nhận.';
            }
          });
        case VoiceRmsSignal():
          break;
        case VoiceTranscriptSignal(:final text, :final isFinal):
          final clean = text.trim();
          setState(() {
            _inputCtrl.text = text;
            _inputCtrl.selection = TextSelection.collapsed(offset: text.length);
            _activeSource = FinancialInputSource.voiceTranscript;
            if (isFinal) {
              _autoEndpointTimer?.cancel();
              _isListening = false;
              _voiceHint = clean.isNotEmpty
                  ? '✓ Đã nhận diện giọng nói — kiểm tra các thẻ xác nhận bên dưới!'
                  : null;
            }
          });
          if (isFinal) {
            if (clean.isNotEmpty) {
              HapticFeedback.mediumImpact();
              _submitAnalysis();
            }
          } else if (clean.isNotEmpty) {
            _scheduleAutoEndpointAndAnalyze(clean);
          }
        case VoiceErrorSignal(:final message):
          _autoEndpointTimer?.cancel();
          final hasPartial = _inputCtrl.text.trim().isNotEmpty;
          setState(() {
            _isListening = false;
            _voiceHint = hasPartial
                ? '✓ Đã giữ câu vừa nói — kiểm tra & xác nhận bên dưới.'
                : message;
          });
          if (hasPartial) {
            _submitAnalysis();
          }
      }
    });

    if (widget.initialText != null && widget.initialText!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _submitAnalysis());
    }
  }

  void _scheduleAutoEndpointAndAnalyze(String liveText) {
    _autoEndpointTimer?.cancel();
    final user = context.read<AuthBloc>().state.user;
    final eval = VoiceUtteranceEvaluator.evaluate(
      liveText,
      currentUserId: user?.id ?? 'u_voice',
      currentUserName: user?.fullName ?? 'Tôi',
    );
    if (mounted) {
      setState(() => _voiceHint = eval.liveStatusVi);
    }

    final wordCount = liveText.split(RegExp(r'\s+')).length;
    if (!eval.isReadyComplete && !eval.hasActionableDraft && wordCount < 4) {
      return;
    }

    _autoEndpointTimer = Timer(eval.silenceAutoStopDelay, () async {
      if (!mounted || !_isListening) return;
      await sl<NativeVoiceAssistantBridge>().stopListening();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _isListening = false;
        _voiceHint =
            '✓ Đã nhận diện chuẩn và tự dừng — mời bạn kiểm tra & xác nhận bên dưới!';
      });
      if (_inputCtrl.text.trim().isNotEmpty) {
        _submitAnalysis();
      }
    });
  }

  @override
  void dispose() {
    _autoEndpointTimer?.cancel();
    _voiceSub?.cancel();
    sl<NativeVoiceAssistantBridge>().stopListening();
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleMic({bool clearExisting = false}) async {
    _autoEndpointTimer?.cancel();
    final bridge = sl<NativeVoiceAssistantBridge>();
    if (_isListening && !clearExisting) {
      await bridge.stopListening();
      if (mounted) {
        setState(() {
          _isListening = false;
          if (_inputCtrl.text.trim().isNotEmpty) {
            _voiceHint =
                '✓ Đã dừng thu âm — kiểm tra các thẻ xác nhận bên dưới.';
          }
        });
        if (_inputCtrl.text.trim().isNotEmpty) {
          _submitAnalysis();
        }
      }
      return;
    }
    if (clearExisting) {
      _inputCtrl.clear();
    }
    setState(() {
      _isListening = true;
      _voiceHint =
          'Đang tự động thu âm — nói xong hệ thống sẽ tự dừng để bạn xác nhận.';
    });
    final res = await bridge.startListening();
    if (!mounted) return;
    if (res == 'UNSUPPORTED' || res == 'ERROR') {
      setState(() {
        _isListening = false;
        _voiceHint =
            'Thiết bị hiện tại chưa bật dịch vụ giọng nói hệ thống; hãy gõ hoặc chọn mẫu câu bên dưới.';
      });
    }
  }

  void _submitAnalysis() {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    final txState = context.read<TransactionListBloc>().state;
    final preferredWallet = txState.wallets.isNotEmpty
        ? txState.wallets.first.id
        : null;

    context.read<FinancialAiBloc>().add(
      FinancialTextSubmitted(
        userId: user.id,
        text: _inputCtrl.text,
        source: _activeSource,
        preferredWalletId: preferredWallet,
        familyId: user.activeFamilyId,
        knownWallets: txState.wallets,
        knownCategories: txState.categories,
      ),
    );

    final dash = _tryReadOptionalBloc<DashboardBloc>(context)?.state.data;
    final snap = GeminiContextSnapshot(
      monthlyIncomeMinor: dash?.monthlyIncomeMinor ?? 0,
      monthlyExpenseMinor: dash?.monthlyExpenseMinor ?? 0,
      upcomingEventsCount: dash?.upcomingEventsCount ?? 0,
      openTasksCount: dash?.openTasksCount ?? 0,
      topHabitLabels: UserBehaviorPrefs.topRankedHabits(limit: 3)
          .map((h) => h.label)
          .toList(),
    );
    context.read<GeminiCopilotBloc>().add(
      GeminiOmniAnalyzeRequested(
        rawInput: _inputCtrl.text,
        contextSnapshot: snap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final txState = context.watch<TransactionListBloc>().state;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return BlocListener<FinancialAiBloc, FinancialAiState>(
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
          LifeOsTopToast.show(
            context,
            state.feedbackMessage!,
            kind: LifeOsToastKind.info,
          );
        }
      },
      child: Scaffold(
        body: LifeOsMintWaveCanvas(
          child: SafeArea(
            child: Column(
              children: [
                LifeOsTopBrandHeader(
                  title: 'Trợ lý AI & Liên kết Gemini',
                  showBackButton: true,
                  extraBrandActions: [
                    LifeOsHeaderCircleButton(
                      icon: Icons.tune_rounded,
                      tooltip: 'Cài đặt AI & Liên kết Gemini',
                      onTap: () => context.push('/financial-ai-settings'),
                    ),
                  ],
                ),
                Expanded(
                  child: BlocBuilder<GeminiCopilotBloc, GeminiCopilotState>(
                    builder: (context, geminiState) {
                      final geminiReady = geminiState.config.isReadyForCloud;
                      final geminiBusy =
                          geminiState.status == GeminiCopilotStatus.analyzing;

                      return BlocBuilder<FinancialAiBloc, FinancialAiState>(
                        builder: (context, aiState) {
                          final meta = aiState.modelMetadata;
                          final isAnalyzing =
                              aiState.status == FinancialAiStatus.analyzing ||
                              geminiBusy;
                          final readyCount = aiState.activeCandidates
                              .where((d) => d.isReadyToConfirm)
                              .length;

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
                                  // 1. Hybrid Offline + Gemini AI Status Banner
                                  LifeOsSoftCard(
                                    onTap: () =>
                                        context.push('/financial-ai-settings'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              geminiReady
                                                  ? Icons.auto_awesome_rounded
                                                  : Icons.offline_bolt_rounded,
                                              size: 19,
                                              color: c.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                meta.usingRuleFallback
                                                    ? 'Quy tắc Nội bộ Offline (${meta.modelVersion})'
                                                    : 'FastText Tiếng Việt · v${meta.modelVersion} (${(meta.sizeBytes / 1024).toStringAsFixed(0)} KB)',
                                                softWrap: true,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: c.textPrimary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            const LifeOsStatusPill(
                                              icon: Icons.shield_outlined,
                                              label: '100% Trên máy',
                                              tone: LifeOsAccentTone.emerald,
                                            ),
                                            LifeOsStatusPill(
                                              icon: geminiReady
                                                  ? Icons.bolt_rounded
                                                  : Icons.add_link_rounded,
                                              label: geminiReady
                                                  ? 'Đã nối Gemini'
                                                  : 'Nối Gemini',
                                              tone: geminiReady
                                                  ? LifeOsAccentTone.emerald
                                                  : LifeOsAccentTone.blue,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                              const SizedBox(height: 12),

                              // 2. AI Transaction Input Card (Phase 16.1)
                              LifeOsMintHeroCard(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Nhập câu tự nhiên, giọng nói hoặc tin nhắn ngân hàng',
                                      softWrap: true,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      key: const Key('financial_ai_text_input'),
                                      controller: _inputCtrl,
                                      minLines: 2,
                                      maxLines: 4,
                                      onChanged: (_) {
                                        if (_activeSource !=
                                            FinancialInputSource.manualText) {
                                          _activeSource =
                                              FinancialInputSource.manualText;
                                        }
                                      },
                                      decoration: InputDecoration(
                                        hintText: 'VD: Đổ xăng 70k, cf 25k',
                                        hintMaxLines: 2,
                                        filled: true,
                                        fillColor: c.surface,
                                        suffixIcon: IconButton(
                                          key: const Key(
                                            'financial_ai_mic_btn',
                                          ),
                                          tooltip: _isListening
                                              ? 'Chốt câu ngay'
                                              : 'Tự động thu âm giọng nói',
                                          onPressed: () => _toggleMic(),
                                          icon: Icon(
                                            _isListening
                                                ? Icons.check_circle_rounded
                                                : Icons.mic_rounded,
                                            color: _isListening
                                                ? const Color(0xFF059669)
                                                : c.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (_voiceHint != null) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _voiceHint!,
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 11.8,
                                                fontWeight: _isListening
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: _isListening
                                                    ? c.primary
                                                    : c.textSecondary,
                                              ),
                                            ),
                                          ),
                                          if (!_isListening &&
                                              _activeSource ==
                                                  FinancialInputSource
                                                      .voiceTranscript &&
                                              _inputCtrl.text
                                                  .trim()
                                                  .isNotEmpty)
                                            TextButton.icon(
                                              key: const Key(
                                                'financial_ai_voice_retry_btn',
                                              ),
                                              style: TextButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                              onPressed: () => _toggleMic(
                                                clearExisting: true,
                                              ),
                                              icon: const Icon(
                                                Icons.mic_rounded,
                                                size: 16,
                                              ),
                                              label: const Text('Nói lại'),
                                            ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: _samplePrompts.map((item) {
                                        return ActionChip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text(
                                            item.$1,
                                            style: const TextStyle(
                                              fontSize: 11.8,
                                            ),
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _inputCtrl.text = item.$2;
                                              _activeSource =
                                                  FinancialInputSource
                                                      .manualText;
                                            });
                                            _submitAnalysis();
                                          },
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          if (aiState
                                                  .activeCandidates
                                                  .isNotEmpty ||
                                              geminiState
                                                  .activeOmniDrafts
                                                  .isNotEmpty) ...[
                                            OutlinedButton(
                                              onPressed: () {
                                                _inputCtrl.clear();
                                                context
                                                    .read<FinancialAiBloc>()
                                                    .add(
                                                      const FinancialAiReset(),
                                                    );
                                                context
                                                    .read<GeminiCopilotBloc>()
                                                    .add(
                                                      const GeminiOmniReset(),
                                                    );
                                              },
                                              child: const Text('Làm mới'),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          Expanded(
                                            child: FilledButton.icon(
                                              key: const Key(
                                                'financial_ai_analyze_btn',
                                              ),
                                              onPressed: isAnalyzing
                                                  ? null
                                                  : _submitAnalysis,
                                              icon: isAnalyzing
                                                  ? const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                  : const Icon(
                                                      Icons.auto_awesome_rounded,
                                                      size: 18,
                                                    ),
                                              label: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  isAnalyzing
                                                      ? 'Đang phân tích...'
                                                      : (geminiReady
                                                            ? 'Phân tích AI + Gemini'
                                                            : 'Phân tích Offline AI'),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // 2.5. Hybrid Gemini / Behavioral Insight + Multi-Domain Actions
                                _GeminiHybridInsightAndOmniActionsSection(
                                  geminiState: geminiState,
                                  hasFinancialAiCandidates:
                                      aiState.activeCandidates.isNotEmpty,
                                  defaultWalletId: txState.wallets.isNotEmpty
                                      ? txState.wallets.first.id
                                      : 'wallet_cash_default',
                                ),

                              // 3. Non-Transaction Safety Notice (e.g. balance / negation / cancel)
                              if (aiState.currentAnalysis != null &&
                                  !aiState
                                      .currentAnalysis!
                                      .hasActionableCandidates &&
                                  aiState
                                          .currentAnalysis!
                                          .nonTransactionReason !=
                                      null)
                                LifeOsSoftCard(
                                  key: const Key(
                                    'financial_ai_non_tx_notice_card',
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.shield_rounded,
                                        color: c.primary,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Đã bảo vệ sổ cái an toàn (0 giao dịch tạo mới)',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              aiState
                                                  .currentAnalysis!
                                                  .nonTransactionReason!,
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 12.6,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              // 4. Multi-Draft AI Classification Preview (Phase 16.2)
                              if (aiState.activeCandidates.isNotEmpty) ...[
                                LifeOsSectionHeader(
                                  title:
                                      'Bản nháp giao dịch đề xuất (${aiState.activeCandidates.length})',
                                  subtitle:
                                      'Kiểm tra hoặc chỉnh sửa số tiền, danh mục, ví & ngày trước khi xác nhận',
                                ),
                                const SizedBox(height: 6),
                                ...aiState.activeCandidates.map(
                                  (draft) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _AiTransactionDraftPreviewCard(
                                      draft: draft,
                                      wallets: txState.wallets,
                                      categories: txState.categories,
                                      isConfirming: aiState.isConfirming,
                                      onEdit: () => _showEditDraftSheet(
                                        context,
                                        userId: user.id,
                                        draft: draft,
                                        wallets: txState.wallets,
                                        categories: txState.categories,
                                      ),
                                      onConfirm: () => context
                                          .read<FinancialAiBloc>()
                                          .add(
                                            FinancialDraftConfirmed(
                                              userId: user.id,
                                              draftId: draft.draftId,
                                            ),
                                          ),
                                      onReject: () => context
                                          .read<FinancialAiBloc>()
                                          .add(
                                            FinancialDraftRejected(
                                              userId: user.id,
                                              draftId: draft.draftId,
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                                if (aiState.activeCandidates.length > 1)
                                  LifeOsPrimaryCtaButton(
                                    key: const Key('confirm_all_ai_drafts_btn'),
                                    icon: Icons.done_all_rounded,
                                    label:
                                        'Xác nhận ghi sổ tất cả ($readyCount/${aiState.activeCandidates.length} khoản hợp lệ)',
                                    onPressed:
                                        (readyCount > 0 &&
                                            !aiState.isConfirming)
                                        ? () => context
                                              .read<FinancialAiBloc>()
                                              .add(
                                                FinancialDraftConfirmed(
                                                  userId: user.id,
                                                ),
                                              )
                                        : null,
                                  ),
                              ],
                                ],
                              ),
                            ),
                          );
                        },
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

  Future<void> _showEditDraftSheet(
    BuildContext context, {
    required String userId,
    required TransactionCandidate draft,
    required List<WalletEntity> wallets,
    required List<CategoryEntity> categories,
  }) async {
    final amountCtrl = TextEditingController(
      text: draft.amountMinor.toString(),
    );
    final descCtrl = TextEditingController(text: draft.description);
    var selectedType = draft.transactionType;
    var selectedCatId = draft.resolvedCategoryId;
    var selectedCatName = draft.resolvedCategoryName;
    var selectedSrcWallet = draft.sourceWalletId;
    var selectedDstWallet = draft.destinationWalletId;
    var selectedDate = draft.occurredAt;
    var learnMerchantRule = true;
    final dateFmt = DateFormat('dd/MM/yyyy');
    final bloc = context.read<FinancialAiBloc>();

    const editableTypes = <FinancialTransactionType>[
      FinancialTransactionType.expense,
      FinancialTransactionType.income,
      FinancialTransactionType.internalTransfer,
      FinancialTransactionType.externalTransfer,
      FinancialTransactionType.refund,
      FinancialTransactionType.loanRepayment,
      FinancialTransactionType.loanDisbursement,
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final c = TammySemanticColors.of(ctx);
          final isTransfer =
              selectedType == FinancialTransactionType.internalTransfer ||
              selectedType == FinancialTransactionType.investmentTransfer;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
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
                      'Chỉnh sửa Bản nháp Giao dịch',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<FinancialTransactionType>(
                      isExpanded: true,
                      initialValue: editableTypes.contains(selectedType)
                          ? selectedType
                          : FinancialTransactionType.expense,
                      decoration: const InputDecoration(
                        labelText: 'Loại giao dịch',
                        isDense: true,
                      ),
                      items: editableTypes
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.displayLabelVi),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setSheetState(() => selectedType = v);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('edit_draft_amount_input'),
                            controller: amountCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Số tiền (VND)',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setSheetState(() {
                                selectedDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                  selectedDate.hour,
                                  selectedDate.minute,
                                );
                              });
                            }
                          },
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                          ),
                          label: Text(dateFmt.format(selectedDate)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mô tả / Cửa hàng',
                        isDense: true,
                      ),
                    ),
                    if (!isTransfer && categories.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        key: const Key('edit_draft_category_dropdown'),
                        isExpanded: true,
                        initialValue:
                            categories.any((cat) => cat.id == selectedCatId)
                            ? selectedCatId
                            : categories.first.id,
                        decoration: const InputDecoration(
                          labelText: 'Danh mục của bạn',
                          isDense: true,
                        ),
                        items: categories
                            .map(
                              (cat) => DropdownMenuItem(
                                value: cat.id,
                                child: Text(cat.name),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val == null) return;
                          final found = categories.firstWhere(
                            (cat) => cat.id == val,
                          );
                          setSheetState(() {
                            selectedCatId = found.id;
                            selectedCatName = found.name;
                          });
                        },
                      ),
                      if (draft.merchantCanonicalKey != null)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Ghi nhớ quy tắc cho cửa hàng này vào lần sau',
                          ),
                          value: learnMerchantRule,
                          onChanged: (v) =>
                              setSheetState(() => learnMerchantRule = v),
                        ),
                    ],
                    if (wallets.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue:
                            wallets.any((w) => w.id == selectedSrcWallet)
                            ? selectedSrcWallet
                            : wallets.first.id,
                        decoration: InputDecoration(
                          labelText: isTransfer
                              ? 'Ví nguồn chuyển đi'
                              : 'Ví thanh toán / nhận tiền',
                          isDense: true,
                        ),
                        items: wallets
                            .map(
                              (w) => DropdownMenuItem(
                                value: w.id,
                                child: Text(w.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setSheetState(() => selectedSrcWallet = v),
                      ),
                      if (isTransfer && wallets.length > 1) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue:
                              wallets.any((w) => w.id == selectedDstWallet)
                              ? selectedDstWallet
                              : wallets
                                    .where((w) => w.id != selectedSrcWallet)
                                    .firstOrNull
                                    ?.id,
                          decoration: const InputDecoration(
                            labelText: 'Ví đích nhận tiền',
                            isDense: true,
                          ),
                          items: wallets
                              .where((w) => w.id != selectedSrcWallet)
                              .map(
                                (w) => DropdownMenuItem(
                                  value: w.id,
                                  child: Text(w.name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setSheetState(() => selectedDstWallet = v),
                        ),
                      ],
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Hủy'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            key: const Key('save_edited_ai_draft_btn'),
                            onPressed: () {
                              final parsedAmt =
                                  VndAmount.tryParseInput(amountCtrl.text) ??
                                  draft.amountMinor;
                              final updated = draft.copyWith(
                                transactionType: selectedType,
                                amountMinor: parsedAmt,
                                description: descCtrl.text.trim().isEmpty
                                    ? draft.description
                                    : descCtrl.text.trim(),
                                resolvedCategoryId: selectedCatId,
                                resolvedCategoryName: selectedCatName,
                                sourceWalletId:
                                    selectedSrcWallet ??
                                    (wallets.isNotEmpty
                                        ? wallets.first.id
                                        : null),
                                destinationWalletId: isTransfer
                                    ? selectedDstWallet
                                    : null,
                                clearDestinationWalletId: !isTransfer,
                                occurredAt: selectedDate,
                              );
                              bloc.add(FinancialCandidateUpdated(updated));
                              if (!isTransfer &&
                                  selectedCatId != null &&
                                  selectedCatId != draft.resolvedCategoryId) {
                                bloc.add(
                                  FinancialCategoryCorrected(
                                    userId: userId,
                                    draftId: draft.draftId,
                                    selectedCategoryId: selectedCatId!,
                                    selectedCategoryName: selectedCatName,
                                    learnRuleForMerchant: learnMerchantRule,
                                  ),
                                );
                              }
                              Navigator.of(ctx).pop();
                            },
                            child: const Text('Áp dụng thay đổi'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AiTransactionDraftPreviewCard extends StatelessWidget {
  final TransactionCandidate draft;
  final List<WalletEntity> wallets;
  final List<CategoryEntity> categories;
  final bool isConfirming;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const _AiTransactionDraftPreviewCard({
    required this.draft,
    required this.wallets,
    required this.categories,
    required this.isConfirming,
    required this.onEdit,
    required this.onConfirm,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final isCredit =
        draft.transactionType == FinancialTransactionType.income ||
        draft.transactionType == FinancialTransactionType.refund;
    final isTransfer =
        draft.transactionType == FinancialTransactionType.internalTransfer ||
        draft.transactionType == FinancialTransactionType.investmentTransfer;

    final srcWalletName =
        wallets.where((w) => w.id == draft.sourceWalletId).firstOrNull?.name ??
        'Chưa chọn ví nguồn';
    final dstWalletName =
        wallets
            .where((w) => w.id == draft.destinationWalletId)
            .firstOrNull
            ?.name ??
        'Chưa chọn ví đích';

    final confTone = switch (draft.confidence.tier) {
      ConfidenceTier.highConfidence => LifeOsAccentTone.emerald,
      ConfidenceTier.mediumConfidence => LifeOsAccentTone.blue,
      ConfidenceTier.lowConfidence => LifeOsAccentTone.amber,
      ConfidenceTier.unknown => LifeOsAccentTone.coral,
    };

    return LifeOsSoftCard(
      key: Key('ai_draft_card_${draft.draftId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProCategoryStyle.buildCategoryBadge(
                draft.resolvedCategoryName,
                isCredit: isCredit,
                isTransfer: isTransfer,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        LifeOsStatusPill(
                          icon: isTransfer
                              ? Icons.swap_horiz_rounded
                              : (isCredit
                                    ? Icons.south_west_rounded
                                    : Icons.north_east_rounded),
                          label: draft.transactionType.displayLabelVi,
                          tone: isTransfer
                              ? LifeOsAccentTone.blue
                              : (isCredit
                                    ? LifeOsAccentTone.emerald
                                    : LifeOsAccentTone.purple),
                        ),
                        LifeOsStatusPill(
                          icon: Icons.verified_outlined,
                          label: draft.confidence.tier.displayLabelVi,
                          tone: confTone,
                        ),
                        if (draft.appliedPersonalizationRuleId != null)
                          const LifeOsStatusPill(
                            icon: Icons.psychology_rounded,
                            label: 'Đã học từ bạn',
                            tone: LifeOsAccentTone.emerald,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      draft.description,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isTransfer
                          ? 'Ví chuyển: $srcWalletName → $dstWalletName'
                          : 'Danh mục: ${draft.resolvedCategoryName} · Ví: $srcWalletName',
                      softWrap: true,
                      style: TextStyle(fontSize: 12.4, color: c.textSecondary),
                    ),
                    Text(
                      'Thời gian: ${dateFmt.format(draft.occurredAt)}',
                      softWrap: true,
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${isCredit ? "+" : (isTransfer ? "" : "-")}${VndAmount.format(draft.amountMinor)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isCredit ? c.primary : c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          if (draft.isDuplicateCandidate) ...[
            const SizedBox(height: 8),
            const LifeOsStatusPill(
              icon: Icons.warning_amber_rounded,
              label:
                  'Cảnh báo: Đã có giao dịch cùng số tiền trong khung 15 phút — kiểm tra tránh ghi trùng!',
              tone: LifeOsAccentTone.coral,
            ),
          ],
          if (draft.ambiguityFlags.contains(
            AmbiguityFlag.ambiguousDecimalOrThousands,
          )) ...[
            const SizedBox(height: 8),
            const LifeOsStatusPill(
              icon: Icons.help_outline_rounded,
              label:
                  'Số tiền có dấu phân cách chưa kèm đơn vị rõ ràng — vui lòng kiểm tra lại số tiền.',
              tone: LifeOsAccentTone.amber,
            ),
          ],
          const Divider(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                key: Key('reject_ai_draft_${draft.draftId}'),
                onPressed: isConfirming ? null : onReject,
                icon: const Icon(Icons.close_rounded, size: 17),
                label: const Text('Bỏ qua'),
              ),
              OutlinedButton.icon(
                key: Key('edit_ai_draft_${draft.draftId}'),
                onPressed: isConfirming ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Sửa'),
              ),
              FilledButton.icon(
                key: Key('confirm_ai_draft_${draft.draftId}'),
                onPressed: (!isConfirming && draft.isReadyToConfirm)
                    ? onConfirm
                    : onEdit,
                icon: Icon(
                  draft.isReadyToConfirm
                      ? Icons.check_rounded
                      : Icons.tune_rounded,
                  size: 17,
                ),
                label: Text(
                  draft.isReadyToConfirm ? 'Xác nhận' : 'Chọn ví / Sửa',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeminiHybridInsightAndOmniActionsSection extends StatelessWidget {
  final GeminiCopilotState geminiState;
  final bool hasFinancialAiCandidates;
  final String defaultWalletId;

  const _GeminiHybridInsightAndOmniActionsSection({
    required this.geminiState,
    required this.hasFinancialAiCandidates,
    required this.defaultWalletId,
  });

  IconData _iconForKind(OmniActionKind kind) => switch (kind) {
    OmniActionKind.transaction => Icons.account_balance_wallet_outlined,
    OmniActionKind.groupSplit => Icons.groups_outlined,
    OmniActionKind.calendarEvent => Icons.event_available_rounded,
    OmniActionKind.task => Icons.task_alt_rounded,
    OmniActionKind.grocery => Icons.shopping_basket_outlined,
    OmniActionKind.waterLog => Icons.water_drop_outlined,
    OmniActionKind.medication => Icons.medication_outlined,
  };

  LifeOsAccentTone _toneForKind(OmniActionKind kind) => switch (kind) {
    OmniActionKind.transaction => LifeOsAccentTone.emerald,
    OmniActionKind.groupSplit => LifeOsAccentTone.blue,
    OmniActionKind.calendarEvent => LifeOsAccentTone.emerald,
    OmniActionKind.task => LifeOsAccentTone.purple,
    OmniActionKind.grocery => LifeOsAccentTone.amber,
    OmniActionKind.waterLog => LifeOsAccentTone.blue,
    OmniActionKind.medication => LifeOsAccentTone.coral,
  };

  @override
  Widget build(BuildContext context) {
    final result = geminiState.lastResult;
    if (result == null) return const SizedBox.shrink();

    final c = TammySemanticColors.of(context);
    final user = context.read<AuthBloc>().state.user;

    // Avoid duplicating financial transaction cards when Offline FastText already rendered them,
    // while surfacing Calendar, Task, Group Split, Grocery (and Gemini-discovered transactions if local missed them).
    final extraDrafts = result.actionDrafts
        .where(
          (d) =>
              !hasFinancialAiCandidates || d.kind != OmniActionKind.transaction,
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LifeOsSoftCard(
          key: const Key('gemini_assistant_insight_card'),
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
                        result.usedGeminiCloud
                            ? Icons.auto_awesome_rounded
                            : Icons.tips_and_updates_outlined,
                        size: 18,
                        color: c.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        result.usedGeminiCloud
                            ? 'Góc nhìn Cố vấn Gemini'
                            : 'Gợi ý Thông minh Trên máy',
                        style: TextStyle(
                          fontSize: 13.8,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  LifeOsStatusPill(
                    label: result.usedGeminiCloud
                        ? 'Gemini · ${result.latencyMs} ms'
                        : 'Offline · ${result.latencyMs} ms',
                    tone: result.usedGeminiCloud
                        ? LifeOsAccentTone.emerald
                        : LifeOsAccentTone.blue,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                result.assistantInsightVi,
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.8,
                  height: 1.38,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (extraDrafts.isNotEmpty) ...[
          LifeOsSectionHeader(
            title: 'Tác vụ liên thông đề xuất (${extraDrafts.length})',
            subtitle:
                'Lịch hẹn, Việc làm, Chia nhóm & Đi chợ bóc tách từ cùng câu lệnh',
            tone: LifeOsAccentTone.blue,
          ),
          const SizedBox(height: 6),
          for (final item in extraDrafts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LifeOsSoftCard(
                key: Key('omni_draft_card_${item.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LifeOsIconSquircle(
                          icon: _iconForKind(item.kind),
                          tone: _toneForKind(item.kind),
                          size: 38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  LifeOsStatusPill(
                                    label: item.badgeLabelVi,
                                    tone: _toneForKind(item.kind),
                                  ),
                                  LifeOsStatusPill(
                                    label: item.originLabel,
                                    tone: LifeOsAccentTone.neutral,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.summaryLineVi,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: c.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton(
                          key: Key('dismiss_omni_${item.id}'),
                          onPressed: () => context
                              .read<GeminiCopilotBloc>()
                              .add(GeminiOmniDraftDismissed(item.id)),
                          child: const Text('Bỏ qua'),
                        ),
                        FilledButton.icon(
                          key: Key('execute_omni_${item.id}'),
                          onPressed: user == null
                              ? null
                              : () async {
                                  final geminiBloc = context
                                      .read<GeminiCopilotBloc>();
                                  await OmniActionExecutor.executeDraft(
                                    toastContext: context,
                                    draft: item,
                                    user: user,
                                    walletId: defaultWalletId,
                                    txActionBloc:
                                        _tryReadOptionalBloc<
                                          TransactionActionBloc
                                        >(context),
                                    calBloc: _tryReadOptionalBloc<CalendarBloc>(
                                      context,
                                    ),
                                    taskBloc: _tryReadOptionalBloc<TaskBloc>(
                                      context,
                                    ),
                                    familyBloc:
                                        _tryReadOptionalBloc<FamilyBloc>(
                                          context,
                                        ),
                                    dailyBloc:
                                        _tryReadOptionalBloc<DailyLifeBloc>(
                                          context,
                                        ),
                                  );
                                  geminiBloc.add(
                                    GeminiOmniDraftDismissed(item.id),
                                  );
                                },
                          icon: const Icon(Icons.check_rounded, size: 17),
                          label: const Text('Thực thi'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
