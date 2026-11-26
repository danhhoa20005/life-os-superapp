import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/services/native_voice_assistant_bridge.dart';
import '../../../../core/utils/omni_action_executor.dart';
import '../../../../core/utils/smart_omni_intent_parser.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../budgets/presentation/bloc/budget_bloc.dart';
import '../../../calendar/presentation/bloc/calendar_bloc.dart';
import '../../../daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../vehicles/presentation/bloc/vehicle_bloc.dart';
import '../../../voice_assistant/data/datasources/local_asr_model_manager.dart';
import '../../../voice_assistant/data/datasources/voice_native_channel_datasource.dart';
import '../../../voice_assistant/data/engines/android_on_device_engine.dart';
import '../../../voice_assistant/data/engines/android_speech_engine.dart';
import '../../../voice_assistant/data/engines/local_asr_engine.dart';
import '../../../voice_assistant/data/engines/system_dialog_engine.dart';
import '../../../voice_assistant/data/repositories/voice_capability_repository_impl.dart';
import '../../../voice_assistant/domain/entities/voice_engine_capability.dart';
import '../../../voice_assistant/domain/entities/voice_session.dart';
import '../../../voice_assistant/domain/services/speech_engine_adapter.dart';
import '../../../voice_assistant/domain/services/voice_session_coordinator.dart';
import '../../../voice_assistant/presentation/bloc/voice_assistant_bloc.dart';
import '../../../voice_assistant/presentation/bloc/voice_assistant_event.dart';
import '../../../voice_assistant/presentation/bloc/voice_assistant_state.dart';
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

class _FinancialAiAssistantBodyState extends State<_FinancialAiAssistantBody>
    with WidgetsBindingObserver {
  static final DateFormat _dateOnlyFmt = DateFormat('dd/MM/yyyy');

  late final TextEditingController _inputCtrl;
  late final VoiceAssistantBloc _voiceBloc;
  bool _ownsLocalVoiceBloc = false;
  final String _ownerId = 'financial_ai_${const Uuid().v4()}';
  Timer? _tapDebounceTimer;
  StreamSubscription<VoiceAssistantState>? _voiceBlocSub;
  VoiceSessionPhase _lastOwnedPhase = VoiceSessionPhase.idle;
  bool _isListening = false;
  bool _isFinalizing = false;
  String? _voiceHint;
  VoiceErrorKind? _lastVoiceErrorKind;
  FinancialInputSource _activeSource = FinancialInputSource.manualText;

  static const int _kTapDebounceMs = 250;

  bool _consumeTapDebounce() {
    if (_tapDebounceTimer?.isActive ?? false) {
      return false;
    }
    _tapDebounceTimer = Timer(
      const Duration(milliseconds: _kTapDebounceMs),
      () {},
    );
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeSource = widget.initialSource;
    _inputCtrl = TextEditingController(text: widget.initialText ?? '');

    final existingBloc = _tryReadOptionalBloc<VoiceAssistantBloc>(context);
    if (existingBloc != null) {
      _voiceBloc = existingBloc;
    } else if (sl.isRegistered<VoiceAssistantBloc>()) {
      _ownsLocalVoiceBloc = true;
      _voiceBloc = sl<VoiceAssistantBloc>();
    } else {
      _ownsLocalVoiceBloc = true;
      final ds = VoiceNativeChannelDataSource(
        client: BridgeAwareVoiceMethodChannelClient(),
      );
      final capRepo = VoiceCapabilityRepositoryImpl(
        store: InMemoryVoiceCapabilityStore(),
      );
      final modelRepo = LocalAsrModelManager.lazy(
        rootDirectoryProvider: () async =>
            Directory('${Directory.systemTemp.path}/lifeos_asr_models'),
      );
      final registry = SpeechEngineRegistry(<SpeechEngineAdapter>[
        AndroidOnDeviceEngine(ds),
        LocalAsrEngine(modelRepository: modelRepo, dataSource: ds),
        AndroidSpeechEngine(ds),
        SystemDialogEngine(ds),
      ]);
      final coordinator = VoiceSessionCoordinator(
        engineRegistry: registry,
        capabilityRepository: capRepo,
        modelRepository: modelRepo,
        initialPreference: VoiceRecognitionPreference.onlineGoogle,
        nativeDiagnosticsProvider: ds.getVoiceDiagnosticsV2,
      );
      _voiceBloc = VoiceAssistantBloc(
        coordinator: coordinator,
        modelRepository: modelRepo,
        disposeCoordinatorOnClose: true,
      );
    }

    _voiceBlocSub = _voiceBloc.stream.listen(_onVoiceStateChanged);

    if (widget.initialText != null && widget.initialText!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _submitAnalysis());
    }
  }

  void _onVoiceStateChanged(VoiceAssistantState vState) {
    if (!mounted || vState.session.ownerId != _ownerId) return;
    final phase = vState.phase;
    final prevPhase = _lastOwnedPhase;
    _lastOwnedPhase = phase;
    final nextText = vState.effectiveText;
    final nextListening = phase.isActiveCapture;
    final nextFinalizing = phase == VoiceSessionPhase.finalizing;
    final nextErrorKind = phase == VoiceSessionPhase.error
        ? vState.session.lastErrorKind
        : null;
    final textChanged =
        nextText.isNotEmpty &&
        nextText != _inputCtrl.text &&
        (phase.isActiveCapture || phase == VoiceSessionPhase.review);
    final nextHint = switch (phase) {
      VoiceSessionPhase.requestingPermission =>
        'Vui lòng bấm Cho phép quyền Micro trên hộp thoại hệ thống...',
      VoiceSessionPhase.preparing => 'Đang mở kênh Micro tiếng Việt...',
      VoiceSessionPhase.listening =>
        'Đang nghe tiếng Việt — bấm Dừng khi nói xong để hệ thống xử lý.',
      VoiceSessionPhase.finalizing => 'Đang hoàn tất câu vừa nói...',
      VoiceSessionPhase.review =>
        nextText.isNotEmpty
            ? '✓ Đã nhận diện giọng nói — kiểm tra các thẻ xác nhận bên dưới!'
            : null,
      VoiceSessionPhase.error =>
        vState.session.lastErrorMessageVi ??
            vState.session.lastErrorKind?.friendlyMessageVi ??
            'Tạm gián đoạn thu âm — mời bạn thử lại.',
      VoiceSessionPhase.cancelled =>
        nextText.isNotEmpty
            ? '✓ Đã giữ câu vừa nói — kiểm tra & xác nhận bên dưới.'
            : 'Đã dừng phiên thu âm.',
      _ => vState.actionableHintVi,
    };

    if (nextListening != _isListening ||
        nextFinalizing != _isFinalizing ||
        nextErrorKind != _lastVoiceErrorKind ||
        nextHint != _voiceHint ||
        textChanged) {
      setState(() {
        _isListening = nextListening;
        _isFinalizing = nextFinalizing;
        _lastVoiceErrorKind = nextErrorKind;
        if (textChanged) {
          _inputCtrl.text = nextText;
          _inputCtrl.selection = TextSelection.collapsed(
            offset: nextText.length,
          );
          _activeSource = FinancialInputSource.voiceTranscript;
        }
        _voiceHint = nextHint;
      });
    }

    if (phase == VoiceSessionPhase.review &&
        prevPhase != VoiceSessionPhase.review &&
        nextText.trim().isNotEmpty) {
      HapticFeedback.mediumImpact();
      _submitAnalysis();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _voiceBloc.isClosed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_voiceBloc.state.session.ownerId == _ownerId) {
        _voiceBloc.add(const VoiceAppLifecycleChanged(true));
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_voiceBloc.state.session.ownerId == _ownerId) {
        _voiceBloc.add(const VoiceAppLifecycleChanged(false));
      }
    }
  }

  @override
  void dispose() {
    _tapDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _voiceBlocSub?.cancel();
    if (!_voiceBloc.isClosed) {
      final activeSession = _voiceBloc.state.session;
      if (activeSession.ownerId == _ownerId &&
          activeSession.sessionId.isNotEmpty &&
          activeSession.phase.isActiveCapture) {
        _voiceBloc.add(
          VoiceCancelRequested(
            sessionId: activeSession.sessionId,
            reason: 'financial_ai_disposed',
          ),
        );
      }
      if (_ownsLocalVoiceBloc) {
        _voiceBloc.close();
      }
    }
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleMic({
    bool clearExisting = false,
    bool preferSystemDialog = false,
  }) async {
    if (!_consumeTapDebounce()) return;
    if (_isFinalizing) return;

    final currentSession = _voiceBloc.state.session;
    if (_isListening &&
        currentSession.ownerId == _ownerId &&
        !clearExisting &&
        !preferSystemDialog) {
      if (currentSession.phase == VoiceSessionPhase.listening) {
        _voiceBloc.add(VoiceStopRequested(sessionId: currentSession.sessionId));
      } else {
        _voiceBloc.add(
          VoiceCancelRequested(
            sessionId: currentSession.sessionId,
            reason: 'user_cancelled',
          ),
        );
      }
      return;
    }

    if (clearExisting) {
      _inputCtrl.clear();
    } else if (_inputCtrl.text.trim().isNotEmpty) {
      _voiceBloc.add(VoiceTranscriptEdited(_inputCtrl.text.trim()));
    }

    final savedModeWire =
        await UserBehaviorPrefs.loadPreferredVoiceEngineMode();
    if (!mounted) return;
    final pref = preferSystemDialog
        ? VoiceRecognitionPreference.systemDialog
        : switch (savedModeWire.trim().toLowerCase()) {
            'offline_strict' ||
            'on_device' => VoiceRecognitionPreference.offlineStrict,
            'system_dialog' ||
            'system_speech_dialog' => VoiceRecognitionPreference.systemDialog,
            'hybrid_auto' || 'auto' => VoiceRecognitionPreference.hybridAuto,
            _ => VoiceRecognitionPreference.onlineGoogle,
          };

    _voiceBloc.add(
      VoiceStartRequested(
        ownerId: _ownerId,
        entryPoint: VoiceEntryPoint.financialAi,
        preference: pref,
        clearTranscript: clearExisting,
      ),
    );
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
    final dashIncome = dash?.monthlyIncomeMinor ?? 0;
    final dashExpense = dash?.monthlyExpenseMinor ?? 0;
    final monthlyIncome = dashIncome > 0
        ? dashIncome
        : txState.summary.monthlyIncomeMinor;
    final monthlyExpense = dashExpense > 0
        ? dashExpense
        : txState.summary.monthlyExpenseMinor;
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final remainingDays = (daysInMonth - now.day + 1).clamp(1, 31);
    final netRemaining = monthlyIncome - monthlyExpense;
    final safeDaily = netRemaining > 0 ? (netRemaining ~/ remainingDays) : 0;
    final snap = GeminiContextSnapshot(
      monthlyIncomeMinor: monthlyIncome,
      monthlyExpenseMinor: monthlyExpense,
      safeDailyAllowanceMinor: safeDaily,
      upcomingEventsCount: dash?.upcomingEventsCount ?? 0,
      openTasksCount: dash?.openTasksCount ?? 0,
      topHabitLabels: UserBehaviorPrefs.topRankedHabits(
        limit: 3,
      ).map((h) => h.label).toList(),
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
    final user = context.select((AuthBloc b) => b.state.user);
    final wallets = context.select((TransactionListBloc b) => b.state.wallets);
    final categories = context.select(
      (TransactionListBloc b) => b.state.categories,
    );
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
                    buildWhen: (p, n) =>
                        p.config.isReadyForCloud != n.config.isReadyForCloud ||
                        p.status != n.status ||
                        p.lastResult != n.lastResult,
                    builder: (context, geminiState) {
                      final geminiReady = geminiState.config.isReadyForCloud;
                      final geminiBusy =
                          geminiState.status == GeminiCopilotStatus.analyzing;

                      return BlocBuilder<FinancialAiBloc, FinancialAiState>(
                        buildWhen: (p, n) =>
                            p.status != n.status ||
                            p.isConfirming != n.isConfirming ||
                            p.currentAnalysis != n.currentAnalysis ||
                            p.activeCandidates != n.activeCandidates ||
                            p.personalizationRules != n.personalizationRules ||
                            p.modelMetadata != n.modelMetadata,
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
                                    key: const Key(
                                      'financial_ai_status_banner_card',
                                    ),
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
                                                    ? 'Agent Local Nội bộ · < 2ms'
                                                    : 'Agent Local Tiếng Việt · v${meta.modelVersion}',
                                                softWrap: true,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: c.textPrimary,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
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
                                            if (aiState
                                                .personalizationRules
                                                .isNotEmpty)
                                              LifeOsStatusPill(
                                                key: const Key(
                                                  'assistant_learned_rules_pill',
                                                ),
                                                icon: Icons.psychology_rounded,
                                                label:
                                                    '${aiState.personalizationRules.length} quy tắc tự học',
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
                                          'Nhập nhanh giao dịch, lịch hẹn hoặc việc làm',
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        TextField(
                                          key: const Key(
                                            'financial_ai_text_input',
                                          ),
                                          controller: _inputCtrl,
                                          minLines: 2,
                                          maxLines: 4,
                                          style: const TextStyle(
                                            fontFeatures: [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                          onChanged: (val) {
                                            setState(() {
                                              if (_activeSource !=
                                                  FinancialInputSource
                                                      .manualText) {
                                                _activeSource =
                                                    FinancialInputSource
                                                        .manualText;
                                              }
                                              if (!_isListening) {
                                                _voiceBloc.add(
                                                  VoiceTranscriptEdited(
                                                    val.trim(),
                                                  ),
                                                );
                                              }
                                            });
                                          },
                                          decoration: InputDecoration(
                                            hintText: 'VD: Phở 45k, cf 25k',
                                            hintMaxLines: 2,
                                            filled: true,
                                            fillColor: c.surface,
                                            suffixIcon: IconButton(
                                              key: const Key(
                                                'financial_ai_mic_btn',
                                              ),
                                              tooltip: _isListening
                                                  ? 'Dừng thu âm'
                                                  : 'Bắt đầu thu âm giọng nói',
                                              onPressed: _isFinalizing
                                                  ? null
                                                  : () => _toggleMic(),
                                              icon: Icon(
                                                _isListening
                                                    ? Icons.stop_circle_rounded
                                                    : Icons.mic_rounded,
                                                color: _isListening
                                                    ? const Color(0xFFDC2626)
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
                                          if (!_isListening &&
                                              _lastVoiceErrorKind != null) ...[
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                if (_lastVoiceErrorKind ==
                                                        VoiceErrorKind
                                                            .permissionDenied ||
                                                    _lastVoiceErrorKind ==
                                                        VoiceErrorKind
                                                            .permissionPermanentlyDenied)
                                                  FilledButton.tonalIcon(
                                                    key: const Key(
                                                      'fin_ai_grant_mic_btn',
                                                    ),
                                                    style:
                                                        FilledButton.styleFrom(
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                        ),
                                                    onPressed: () async {
                                                      if (_lastVoiceErrorKind ==
                                                          VoiceErrorKind
                                                              .permissionPermanentlyDenied) {
                                                        await sl<
                                                              NativeVoiceAssistantBridge
                                                            >()
                                                            .openMicrophoneSettings();
                                                      } else {
                                                        await _toggleMic();
                                                      }
                                                    },
                                                    icon: const Icon(
                                                      Icons
                                                          .mic_external_on_rounded,
                                                      size: 15,
                                                    ),
                                                    label: Text(
                                                      _lastVoiceErrorKind ==
                                                              VoiceErrorKind
                                                                  .permissionPermanentlyDenied
                                                          ? 'Mở Cài đặt Micro'
                                                          : 'Cấp quyền Micro',
                                                      style: const TextStyle(
                                                        fontSize: 11.5,
                                                      ),
                                                    ),
                                                  ),
                                                OutlinedButton.icon(
                                                  key: const Key(
                                                    'fin_ai_system_voice_btn',
                                                  ),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                      ),
                                                  onPressed: () => _toggleMic(
                                                    preferSystemDialog: true,
                                                  ),
                                                  icon: const Icon(
                                                    Icons
                                                        .record_voice_over_outlined,
                                                    size: 15,
                                                  ),
                                                  label: const Text(
                                                    'Thu âm hệ thống',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                        if (_inputCtrl.text.trim().isEmpty &&
                                            aiState.activeCandidates.isEmpty &&
                                            aiState.currentAnalysis == null &&
                                            geminiState.lastResult == null) ...[
                                          const SizedBox(height: 10),
                                          Text(
                                            'Mẫu câu lệnh gợi ý 1-chạm',
                                            style: TextStyle(
                                              fontSize: 11.8,
                                              fontWeight: FontWeight.w700,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              for (final sample in const [
                                                (
                                                  key: 'expense',
                                                  label: 'Cà phê 35k',
                                                  icon:
                                                      Icons.local_cafe_outlined,
                                                  command: 'Cà phê 35k',
                                                ),
                                                (
                                                  key: 'split',
                                                  label: 'Chia bill 240k',
                                                  icon: Icons.groups_outlined,
                                                  command:
                                                      'Ăn trưa 240k chia 4 người',
                                                ),
                                                (
                                                  key: 'schedule',
                                                  label: 'Họp 9h sáng mai',
                                                  icon: Icons
                                                      .event_available_rounded,
                                                  command:
                                                      'Họp dự án 9h sáng mai',
                                                ),
                                                (
                                                  key: 'water',
                                                  label: 'Uống 250ml nước',
                                                  icon:
                                                      Icons.water_drop_outlined,
                                                  command: 'Uống 250ml nước',
                                                ),
                                              ])
                                                ActionChip(
                                                  key: Key(
                                                    'ai_sample_chip_${sample.key}',
                                                  ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  avatar: Icon(
                                                    sample.icon,
                                                    size: 15,
                                                    color: c.primary,
                                                  ),
                                                  label: Text(
                                                    sample.label,
                                                    style: const TextStyle(
                                                      fontSize: 11.8,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontFeatures: [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                    ),
                                                  ),
                                                  onPressed: isAnalyzing
                                                      ? null
                                                      : () {
                                                          setState(() {
                                                            _activeSource =
                                                                FinancialInputSource
                                                                    .manualText;
                                                            _inputCtrl.text =
                                                                sample.command;
                                                            _inputCtrl
                                                                    .selection =
                                                                TextSelection.collapsed(
                                                                  offset: sample
                                                                      .command
                                                                      .length,
                                                                );
                                                          });
                                                          _voiceBloc.add(
                                                            VoiceTranscriptEdited(
                                                              sample.command,
                                                            ),
                                                          );
                                                          _submitAnalysis();
                                                        },
                                                ),
                                            ],
                                          ),
                                        ],
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
                                                  setState(() {
                                                    _inputCtrl.clear();
                                                    _voiceHint = null;
                                                    _lastVoiceErrorKind = null;
                                                    _activeSource =
                                                        FinancialInputSource
                                                            .manualText;
                                                  });
                                                  _voiceBloc.add(
                                                    const VoiceResetToIdleRequested(
                                                      clearTranscript: true,
                                                    ),
                                                  );
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
                                                        Icons
                                                            .auto_awesome_rounded,
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
                                    defaultWalletId: wallets.isNotEmpty
                                        ? wallets.first.id
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
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: _AiTransactionDraftPreviewCard(
                                          draft: draft,
                                          wallets: wallets,
                                          categories: categories,
                                          isConfirming: aiState.isConfirming,
                                          onEdit: () => _showEditDraftSheet(
                                            context,
                                            userId: user.id,
                                            draft: draft,
                                            wallets: wallets,
                                            categories: categories,
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
                                        key: const Key(
                                          'confirm_all_ai_drafts_btn',
                                        ),
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
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
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
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _dateOnlyFmt.format(selectedDate),
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
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
  static final DateFormat _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

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
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            draft.description,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            '${isCredit ? "+" : (isTransfer ? "" : "-")}${VndAmount.format(draft.amountMinor)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isCredit ? c.primary : c.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
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
                      'Thời gian: ${_dateTimeFmt.format(draft.occurredAt)}',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
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

class _GeminiHybridInsightAndOmniActionsSection extends StatefulWidget {
  final GeminiCopilotState geminiState;
  final bool hasFinancialAiCandidates;
  final String defaultWalletId;

  const _GeminiHybridInsightAndOmniActionsSection({
    required this.geminiState,
    required this.hasFinancialAiCandidates,
    required this.defaultWalletId,
  });

  @override
  State<_GeminiHybridInsightAndOmniActionsSection> createState() =>
      _GeminiHybridInsightAndOmniActionsSectionState();
}

class _GeminiHybridInsightAndOmniActionsSectionState
    extends State<_GeminiHybridInsightAndOmniActionsSection> {
  static final DateFormat _dateOnlyFmt = DateFormat('dd/MM/yyyy');
  static final DateFormat _timeOnlyFmt = DateFormat('HH:mm');

  final Set<String> _executingOmniIds = <String>{};
  final Map<String, OmniActionDraft> _editedOmniOverrides =
      <String, OmniActionDraft>{};

  @override
  void didUpdateWidget(
    covariant _GeminiHybridInsightAndOmniActionsSection oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.geminiState.lastResult != widget.geminiState.lastResult) {
      final validIds = widget.geminiState.activeOmniDrafts
          .map((d) => d.id)
          .toSet();
      _editedOmniOverrides.removeWhere((id, _) => !validIds.contains(id));
    }
  }

  IconData _iconForKind(OmniActionKind kind) => switch (kind) {
    OmniActionKind.transaction => Icons.account_balance_wallet_outlined,
    OmniActionKind.groupSplit => Icons.groups_outlined,
    OmniActionKind.calendarEvent => Icons.event_available_rounded,
    OmniActionKind.task => Icons.task_alt_rounded,
    OmniActionKind.grocery => Icons.shopping_basket_outlined,
    OmniActionKind.waterLog => Icons.water_drop_outlined,
  };

  LifeOsAccentTone _toneForKind(OmniActionKind kind) => switch (kind) {
    OmniActionKind.transaction => LifeOsAccentTone.emerald,
    OmniActionKind.groupSplit => LifeOsAccentTone.blue,
    OmniActionKind.calendarEvent => LifeOsAccentTone.emerald,
    OmniActionKind.task => LifeOsAccentTone.purple,
    OmniActionKind.grocery => LifeOsAccentTone.amber,
    OmniActionKind.waterLog => LifeOsAccentTone.blue,
  };

  bool _supportsAmount(OmniActionDraft draft) =>
      draft.kind == OmniActionKind.transaction ||
      draft.kind == OmniActionKind.groupSplit ||
      draft.kind == OmniActionKind.grocery ||
      draft.amountMinor > 0;

  bool _supportsSchedule(OmniActionDraft draft) =>
      draft.kind == OmniActionKind.calendarEvent ||
      draft.kind == OmniActionKind.task ||
      draft.scheduledAt != null;

  Future<void> _showQuickEditOmniSheet(
    BuildContext context,
    OmniActionDraft draft,
  ) async {
    final titleCtrl = TextEditingController(text: draft.title);
    final amountCtrl = TextEditingController(
      text: draft.amountMinor > 0 ? '${draft.amountMinor}' : '',
    );
    var scheduledAt = draft.scheduledAt ?? DateTime.now();
    final showAmount = _supportsAmount(draft);
    final showSchedule = _supportsSchedule(draft);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final c = TammySemanticColors.of(ctx);
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
                      'Sửa nhanh tác vụ (${draft.badgeLabelVi})',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('edit_omni_title_input'),
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tiêu đề',
                        isDense: true,
                      ),
                    ),
                    if (showAmount) ...[
                      const SizedBox(height: 10),
                      TextField(
                        key: const Key('edit_omni_amount_input'),
                        controller: amountCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Số tiền (VND)',
                          isDense: true,
                        ),
                      ),
                    ],
                    if (showSchedule) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (draft.kind == OmniActionKind.calendarEvent ||
                              draft.kind == OmniActionKind.task)
                            OutlinedButton.icon(
                              key: const Key('edit_omni_date_btn'),
                              onPressed: () async {
                                final pickedDate = await showDatePicker(
                                  context: ctx,
                                  initialDate: scheduledAt,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (pickedDate != null) {
                                  setSheetState(() {
                                    scheduledAt = DateTime(
                                      pickedDate.year,
                                      pickedDate.month,
                                      pickedDate.day,
                                      scheduledAt.hour,
                                      scheduledAt.minute,
                                    );
                                  });
                                }
                              },
                              icon: const Icon(
                                Icons.calendar_today_rounded,
                                size: 16,
                              ),
                              label: Text(
                                _dateOnlyFmt.format(scheduledAt),
                                style: const TextStyle(
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          OutlinedButton.icon(
                            key: const Key('edit_omni_time_btn'),
                            onPressed: () async {
                              final pickedTime = await showTimePicker(
                                context: ctx,
                                initialTime: TimeOfDay.fromDateTime(
                                  scheduledAt,
                                ),
                              );
                              if (pickedTime != null) {
                                setSheetState(() {
                                  scheduledAt = DateTime(
                                    scheduledAt.year,
                                    scheduledAt.month,
                                    scheduledAt.day,
                                    pickedTime.hour,
                                    pickedTime.minute,
                                  );
                                });
                              }
                            },
                            icon: const Icon(Icons.schedule_rounded, size: 16),
                            label: Text(
                              'Giờ hẹn: ${_timeOnlyFmt.format(scheduledAt)}',
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ),
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
                            key: const Key('save_edited_omni_btn'),
                            onPressed: () {
                              final cleanTitle = titleCtrl.text.trim();
                              if (cleanTitle.isEmpty) {
                                LifeOsTopToast.show(
                                  ctx,
                                  'Vui lòng nhập tiêu đề tác vụ.',
                                  kind: LifeOsToastKind.warning,
                                );
                                return;
                              }
                              var nextAmount = draft.amountMinor;
                              if (showAmount) {
                                final parsed = VndAmount.tryParseInput(
                                  amountCtrl.text,
                                );
                                if ((draft.kind == OmniActionKind.transaction ||
                                        draft.kind ==
                                            OmniActionKind.groupSplit) &&
                                    (parsed == null || parsed <= 0)) {
                                  LifeOsTopToast.show(
                                    ctx,
                                    'Vui lòng nhập số tiền hợp lệ (> 0 ₫).',
                                    kind: LifeOsToastKind.warning,
                                  );
                                  return;
                                }
                                if (parsed != null && parsed > 0) {
                                  nextAmount = parsed;
                                } else if (amountCtrl.text.trim().isEmpty) {
                                  nextAmount = 0;
                                }
                              }
                              final updated = OmniActionDraft(
                                id: draft.id,
                                kind: draft.kind,
                                title: cleanTitle,
                                amountMinor: nextAmount,
                                transactionKind: draft.transactionKind,
                                categoryId: draft.categoryId,
                                categoryName: draft.categoryName,
                                participantCount: draft.participantCount,
                                participantNames: draft.participantNames,
                                scheduledAt: showSchedule
                                    ? scheduledAt
                                    : draft.scheduledAt,
                                durationMinutes: draft.durationMinutes,
                                location: draft.location,
                                taskPriority: draft.taskPriority,
                                quantityLabel: draft.quantityLabel,
                                waterMl: draft.waterMl,
                                originLabel: draft.originLabel,
                              );
                              setState(() {
                                _editedOmniOverrides[draft.id] = updated;
                              });
                              Navigator.of(ctx).pop();
                            },
                            child: const Text('Áp dụng'),
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
    titleCtrl.dispose();
    amountCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.geminiState.lastResult;
    if (result == null) return const SizedBox.shrink();

    final c = TammySemanticColors.of(context);
    final user = context.read<AuthBloc>().state.user;

    // Avoid duplicating financial transaction cards when Offline FastText already rendered them,
    // while surfacing Calendar, Task, Group Split, Grocery (and Gemini-discovered transactions if local missed them).
    final extraDrafts = result.actionDrafts
        .where(
          (d) =>
              !widget.hasFinancialAiCandidates ||
              d.kind != OmniActionKind.transaction,
        )
        .toList(growable: false);

    final showInsightCard =
        result.usedGeminiCloud ||
        (!widget.hasFinancialAiCandidates && extraDrafts.isEmpty);

    if (!showInsightCard && extraDrafts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showInsightCard) ...[
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
                        Flexible(
                          child: Text(
                            result.usedGeminiCloud
                                ? 'Góc nhìn Cố vấn Gemini'
                                : 'Gợi ý Thông minh Trên máy',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 13.8,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
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
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.geminiState.lastResult != null) ...[
          Builder(
            builder: (context) {
              final blocked = SmartOmniIntentParser.parseDetailed(
                widget.geminiState.lastResult!.originalInput,
              ).blockedClauses;
              if (blocked.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LifeOsSoftCard(
                  key: const Key('ai_assistant_blocked_clauses_card'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, size: 18, color: c.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Đã chặn vế không phát sinh giao dịch: ${blocked.map((b) => '"${b.clause}" (${b.reasonVi})').join(' · ')}',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 12.2,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
        if (extraDrafts.isNotEmpty) ...[
          LifeOsSectionHeader(
            title: 'Tác vụ liên thông đề xuất (${extraDrafts.length})',
            subtitle:
                'Lịch hẹn, Việc làm, Chia nhóm & Đi chợ bóc tách từ cùng câu lệnh',
            tone: LifeOsAccentTone.blue,
          ),
          const SizedBox(height: 6),
          for (final rawItem in extraDrafts)
            Builder(
              builder: (context) {
                final item = _editedOmniOverrides[rawItem.id] ?? rawItem;
                final isExecuting = _executingOmniIds.contains(item.id);
                return Padding(
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
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
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
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
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
                              onPressed: isExecuting
                                  ? null
                                  : () {
                                      _editedOmniOverrides.remove(item.id);
                                      context.read<GeminiCopilotBloc>().add(
                                        GeminiOmniDraftDismissed(item.id),
                                      );
                                    },
                              child: const Text('Bỏ qua'),
                            ),
                            OutlinedButton.icon(
                              key: Key('edit_omni_${item.id}'),
                              onPressed: isExecuting
                                  ? null
                                  : () =>
                                        _showQuickEditOmniSheet(context, item),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Sửa nhanh'),
                            ),
                            FilledButton.icon(
                              key: Key('execute_omni_${item.id}'),
                              onPressed: (user == null || isExecuting)
                                  ? null
                                  : () async {
                                      if (_executingOmniIds.contains(item.id)) {
                                        return;
                                      }
                                      setState(
                                        () => _executingOmniIds.add(item.id),
                                      );
                                      final geminiBloc = context
                                          .read<GeminiCopilotBloc>();
                                      try {
                                        final ok =
                                            await OmniActionExecutor.executeDraft(
                                              toastContext: context,
                                              draft: item,
                                              user: user,
                                              walletId: widget.defaultWalletId,
                                              availableWallets:
                                                  _tryReadOptionalBloc<
                                                        TransactionListBloc
                                                      >(context)
                                                      ?.state
                                                      .wallets ??
                                                  const <WalletEntity>[],
                                              txActionBloc:
                                                  _tryReadOptionalBloc<
                                                    TransactionActionBloc
                                                  >(context),
                                              calBloc:
                                                  _tryReadOptionalBloc<
                                                    CalendarBloc
                                                  >(context),
                                              taskBloc:
                                                  _tryReadOptionalBloc<
                                                    TaskBloc
                                                  >(context),
                                              familyBloc:
                                                  _tryReadOptionalBloc<
                                                    FamilyBloc
                                                  >(context),
                                              dailyBloc:
                                                  _tryReadOptionalBloc<
                                                    DailyLifeBloc
                                                  >(context),
                                              budgetBloc:
                                                  _tryReadOptionalBloc<
                                                    BudgetBloc
                                                  >(context),
                                              vehicleBloc:
                                                  _tryReadOptionalBloc<
                                                    VehicleBloc
                                                  >(context),
                                            );
                                        if (ok && mounted) {
                                          _editedOmniOverrides.remove(item.id);
                                          geminiBloc.add(
                                            GeminiOmniDraftDismissed(item.id),
                                          );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(
                                            () => _executingOmniIds.remove(
                                              item.id,
                                            ),
                                          );
                                        } else {
                                          _executingOmniIds.remove(item.id);
                                        }
                                      }
                                    },
                              icon: isExecuting
                                  ? const SizedBox(
                                      width: 15,
                                      height: 15,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded, size: 17),
                              label: Text(
                                isExecuting ? 'Đang thực thi...' : 'Thực thi',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ],
    );
  }
}
