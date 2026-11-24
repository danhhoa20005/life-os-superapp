import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/authentication/domain/entities/user_entity.dart';
import '../../features/authentication/presentation/bloc/auth_bloc.dart';
import '../../features/calendar/presentation/bloc/calendar_bloc.dart';
import '../../features/daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../features/family/domain/entities/family_entities.dart';
import '../../features/family/domain/usecases/family_usecases.dart';
import '../../features/family/presentation/bloc/family_bloc.dart';
import '../../features/financial_ai/domain/entities/financial_ai_entities.dart';
import '../../features/tasks/presentation/bloc/task_bloc.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import '../../features/transactions/presentation/bloc/transaction_bloc.dart';
import '../../features/transactions/presentation/bloc/transaction_event.dart';
import '../di/dependency_injection.dart';
import '../services/native_voice_assistant_bridge.dart';
import '../utils/omni_action_executor.dart';
import '../utils/smart_omni_intent_parser.dart';
import '../utils/user_behavior_prefs.dart';
import '../utils/vnd_amount.dart';
import '../utils/voice_financial_nlp_engine.dart';
import '../utils/voice_utterance_completeness.dart';
import 'lifeos_top_toast.dart';
import 'pro_max_widgets.dart';
import 'status_widgets.dart';

T? _tryReadBloc<T extends StateStreamableSource<Object?>>(BuildContext ctx) {
  try {
    return ctx.read<T>();
  } catch (_) {
    return null;
  }
}

Future<void> showVoiceSmartCaptureSheet(
  BuildContext context, {
  bool? autoStartListening,
  String? initialTranscript,
}) async {
  final authUser = context.read<AuthBloc>().state.user;
  if (authUser == null) return;

  final txListBloc = context.read<TransactionListBloc>();
  final txActionBloc = context.read<TransactionActionBloc>();
  final familyBloc = context.read<FamilyBloc>();
  final calBloc = _tryReadBloc<CalendarBloc>(context);
  final taskBloc = _tryReadBloc<TaskBloc>(context);
  final dailyBloc = _tryReadBloc<DailyLifeBloc>(context);

  final hasPrefilledText =
      initialTranscript != null && initialTranscript.trim().isNotEmpty;
  final effectiveAutoStart = autoStartListening ?? !hasPrefilledText;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      return MultiBlocProvider(
        providers: [
          BlocProvider<TransactionListBloc>.value(value: txListBloc),
          BlocProvider<TransactionActionBloc>.value(value: txActionBloc),
          BlocProvider<FamilyBloc>.value(value: familyBloc),
          if (calBloc != null) BlocProvider<CalendarBloc>.value(value: calBloc),
          if (taskBloc != null) BlocProvider<TaskBloc>.value(value: taskBloc),
          if (dailyBloc != null)
            BlocProvider<DailyLifeBloc>.value(value: dailyBloc),
        ],
        child: _VoiceSmartCaptureSheetBody(
          parentContext: context,
          user: authUser,
          autoStartListening: effectiveAutoStart,
          initialTranscript: initialTranscript,
        ),
      );
    },
  );
}

class _VoiceSmartCaptureSheetBody extends StatefulWidget {
  final BuildContext parentContext;
  final UserEntity user;
  final bool autoStartListening;
  final String? initialTranscript;

  const _VoiceSmartCaptureSheetBody({
    required this.parentContext,
    required this.user,
    required this.autoStartListening,
    this.initialTranscript,
  });

  @override
  State<_VoiceSmartCaptureSheetBody> createState() =>
      _VoiceSmartCaptureSheetBodyState();
}

class _VoiceSmartCaptureSheetBodyState
    extends State<_VoiceSmartCaptureSheetBody> {
  static const List<({String chip, String sentence})> _voiceExamples = [
    (
      chip: '🍜 Phở 55k + Xăng 70k',
      sentence: 'Ăn phở 55 nghìn và đổ xăng 70 nghìn',
    ),
    (
      chip: '🍲 Chia đều 3 người',
      sentence: 'Ăn lẩu bò bốn trăm năm mươi nghìn chia đều 3 người',
    ),
    (
      chip: '💧 Uống nước 300ml',
      sentence: 'Uống 300ml nước lọc',
    ),
    (
      chip: '💊 Nhắc uống thuốc',
      sentence: 'Nhắc uống thuốc vitamin lúc 20h00',
    ),
    (
      chip: '📅 Lịch họp 9h mai',
      sentence: 'Họp nhóm lúc 9h sáng mai',
    ),
  ];

  late final TextEditingController _textCtrl;
  StreamSubscription<VoiceAssistantSignal>? _voiceSub;
  Timer? _autoEndpointTimer;
  bool _isListening = false;
  bool _awaitingConfirmation = false;
  double _rmsDb = 0.0;
  String? _voiceStatusHint;
  String? _selectedWalletId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTranscript?.trim() ?? '';
    _textCtrl = TextEditingController(text: initial);
    _awaitingConfirmation = initial.isNotEmpty;
    UserBehaviorPrefs.loadLastWalletId().then((savedId) {
      if (mounted && savedId != null && _selectedWalletId == null) {
        setState(() => _selectedWalletId = savedId);
      }
    });

    final bridge = sl<NativeVoiceAssistantBridge>();
    _voiceSub = bridge.watchSignals().listen(_handleVoiceSignal);

    if (widget.autoStartListening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startListeningFresh();
      });
    }
  }

  @override
  void dispose() {
    _autoEndpointTimer?.cancel();
    _voiceSub?.cancel();
    sl<NativeVoiceAssistantBridge>().stopListening();
    _textCtrl.dispose();
    super.dispose();
  }

  List<FamilyMemberInfo> _currentKnownMembers() {
    if (!mounted) return const <FamilyMemberInfo>[];
    return context.read<FamilyBloc>().state.activeFamily?.members ??
        const <FamilyMemberInfo>[];
  }

  void _handleVoiceSignal(VoiceAssistantSignal sig) {
    if (!mounted) return;
    switch (sig) {
      case VoiceStateSignal(:final status):
        setState(() {
          if (status == 'listening') {
            _isListening = true;
            _awaitingConfirmation = false;
            _voiceStatusHint = null;
          } else if (status == 'processing') {
            _voiceStatusHint = 'Đang chốt câu vừa nói...';
          }
        });
      case VoiceRmsSignal(:final rmsDb):
        setState(() => _rmsDb = rmsDb);
      case VoiceTranscriptSignal(:final text, :final isFinal):
        final clean = text.trim();
        setState(() {
          _textCtrl.text = text;
          _textCtrl.selection = TextSelection.collapsed(offset: text.length);
          if (isFinal) {
            _autoEndpointTimer?.cancel();
            _isListening = false;
            _rmsDb = 0.0;
            _awaitingConfirmation = clean.isNotEmpty;
            _voiceStatusHint = clean.isNotEmpty
                ? 'Đã tự động ngắt thu âm — kiểm tra & bấm Xác nhận bên dưới.'
                : null;
          }
        });
        if (isFinal) {
          if (clean.isNotEmpty) {
            HapticFeedback.mediumImpact();
          }
        } else if (clean.isNotEmpty) {
          _scheduleSmartAutoEndpoint(clean);
        }
      case VoiceErrorSignal(:final message):
        _autoEndpointTimer?.cancel();
        setState(() {
          _isListening = false;
          _rmsDb = 0.0;
          if (_textCtrl.text.trim().isNotEmpty) {
            _awaitingConfirmation = true;
            _voiceStatusHint =
                'Đã giữ lại nội dung vừa nghe — mời bạn kiểm tra & xác nhận.';
          } else {
            _voiceStatusHint = message;
          }
        });
    }
  }

  /// Automatically stops recording once the spoken Vietnamese sentence is semantically
  /// complete and the user pauses naturally — no manual stop button tap needed!
  void _scheduleSmartAutoEndpoint(String liveText) {
    _autoEndpointTimer?.cancel();
    final eval = VoiceUtteranceEvaluator.evaluate(
      liveText,
      currentUserId: widget.user.id,
      currentUserName: widget.user.fullName,
      knownMembers: _currentKnownMembers(),
    );

    final wordCount = liveText.split(RegExp(r'\s+')).length;
    final shouldArmAutoStop = eval.isReadyComplete ||
        eval.hasActionableDraft ||
        wordCount >= 4;
    if (!shouldArmAutoStop) return;

    _autoEndpointTimer = Timer(eval.silenceAutoStopDelay, () async {
      if (!mounted || !_isListening) return;
      await sl<NativeVoiceAssistantBridge>().stopListening();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _isListening = false;
        _rmsDb = 0.0;
        _awaitingConfirmation = _textCtrl.text.trim().isNotEmpty;
        _voiceStatusHint = eval.isReadyComplete
            ? 'Đã nhận diện đủ ý và tự dừng — mời bạn xác nhận.'
            : 'Đã tạm dừng thu âm — kiểm tra lại nội dung trước khi lưu.';
      });
    });
  }

  Future<void> _startListeningFresh({bool clearExisting = false}) async {
    _autoEndpointTimer?.cancel();
    final bridge = sl<NativeVoiceAssistantBridge>();
    if (clearExisting) {
      _textCtrl.clear();
    }
    setState(() {
      _isListening = true;
      _awaitingConfirmation = false;
      _rmsDb = 0.0;
      _voiceStatusHint = null;
    });
    final res = await bridge.startListening();
    if (!mounted) return;
    if (res == 'UNSUPPORTED' || res == 'ERROR') {
      setState(() {
        _isListening = false;
        _voiceStatusHint =
            'Thiết bị hiện chưa bật dịch vụ thu âm hệ thống — bạn có thể chọn mẫu câu hoặc nhập bên dưới.';
      });
    }
  }

  Future<void> _toggleVoiceListening() async {
    final bridge = sl<NativeVoiceAssistantBridge>();
    if (_isListening) {
      _autoEndpointTimer?.cancel();
      await bridge.stopListening();
      if (mounted) {
        HapticFeedback.lightImpact();
        setState(() {
          _isListening = false;
          _rmsDb = 0.0;
          _awaitingConfirmation = _textCtrl.text.trim().isNotEmpty;
          if (_awaitingConfirmation) {
            _voiceStatusHint = 'Đã dừng thu âm — mời bạn kiểm tra & xác nhận.';
          }
        });
      }
      return;
    }
    await _startListeningFresh();
  }

  Future<void> _pasteFromClipboard() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = clip?.text?.trim() ?? '';
    if (txt.isEmpty) {
      if (mounted) {
        setState(() => _voiceStatusHint = 'Bộ nhớ tạm hiện đang trống.');
      }
      return;
    }
    setState(() {
      _textCtrl.text = txt;
      _awaitingConfirmation = true;
      _voiceStatusHint = 'Đã đọc nội dung từ bộ nhớ tạm — mời bạn xác nhận!';
    });
  }

  static IconData _iconForOmniKind(OmniActionKind kind) => switch (kind) {
        OmniActionKind.transaction => Icons.account_balance_wallet_outlined,
        OmniActionKind.groupSplit => Icons.groups_outlined,
        OmniActionKind.calendarEvent => Icons.event_available_rounded,
        OmniActionKind.task => Icons.task_alt_rounded,
        OmniActionKind.grocery => Icons.shopping_basket_outlined,
        OmniActionKind.waterLog => Icons.water_drop_rounded,
        OmniActionKind.medication => Icons.medication_outlined,
      };

  Future<void> _confirmAndCommit({
    required BuildContext context,
    required VoiceUtteranceEvaluation eval,
    required String targetWalletId,
    required FamilyEntity? activeFamily,
  }) async {
    const uuid = Uuid();
    final navigator = Navigator.of(context);
    final txActionBloc = context.read<TransactionActionBloc>();
    final familyBloc = context.read<FamilyBloc>();
    final calBloc = _tryReadBloc<CalendarBloc>(context);
    final taskBloc = _tryReadBloc<TaskBloc>(context);
    final dailyBloc = _tryReadBloc<DailyLifeBloc>(context);
    final finResult = eval.financialAnalysis;

    // Path A: Rich Financial / Group Split / Multi-Category Receipt
    if (finResult != null) {
      await UserBehaviorPrefs.rememberWallet(targetWalletId);
      switch (finResult.intentKind) {
        case VoiceSentenceIntentKind.groupBillSplit:
          final split = finResult.groupSplit!;
          var targetFamilyId = activeFamily?.id;
          if (targetFamilyId == null) {
            familyBloc.add(
              FamilyCreateSubmitted(
                userId: widget.user.id,
                userName: widget.user.fullName,
                familyName: 'Nhóm Chia Tiền Nhanh',
                spaceType: CollaborationSpaceType.group,
              ),
            );
            final nextFamState = await familyBloc.stream
                .firstWhere(
                  (s) => s.activeFamily != null || s.failure != null,
                )
                .timeout(
                  const Duration(seconds: 4),
                  onTimeout: () => familyBloc.state,
                );
            targetFamilyId = nextFamState.activeFamily?.id;
          }
          if (targetFamilyId == null) {
            if (widget.parentContext.mounted) {
              LifeOsTopToast.show(
                widget.parentContext,
                'Chưa thể khởi tạo nhóm chia tiền — vui lòng thử lại.',
                kind: LifeOsToastKind.warning,
              );
            }
            return;
          }
          familyBloc.add(
            SharedBillSplitCreated(
              CreateSharedBillSplitParams(
                familyId: targetFamilyId,
                title: split.title,
                topic: split.topic,
                paidByUserId: widget.user.id,
                paidByName: widget.user.fullName,
                totalAmountMinor: split.totalAmountMinor,
                splitMethod: split.splitMethod,
                participantIds: split.shares
                    .map((s) => s.participantId)
                    .toList(),
                participantNames: {
                  for (final s in split.shares) s.participantId: s.displayName,
                },
                rawInputValuesByUserId: split.rawInputValuesByUserId,
                choreOrTaskNote: 'Xác nhận từ Giọng nói AI',
              ),
            ),
          );
          if (mounted) {
            navigator.pop();
          }
          if (widget.parentContext.mounted) {
            LifeOsTopToast.show(
              widget.parentContext,
              '✓ Đã chia hóa đơn "${split.title}" (${VndAmount.format(split.totalAmountMinor)}) cho ${split.shares.length} người!',
            );
          }
          return;

        case VoiceSentenceIntentKind.multiCategoryReceipt:
          final rec = finResult.multiCategoryReceipt!;
          txActionBloc.add(
            TransactionCreateSubmitted(
              operationId: uuid.v4(),
              userId: widget.user.id,
              walletId: targetWalletId,
              categoryName: rec.splitLines.first.categoryName,
              kind: TransactionKind.expense,
              amountMinor: rec.totalAmountMinor,
              merchant: rec.merchant,
              note: 'Tách khoản bằng Giọng nói AI',
              occurredAt: DateTime.now(),
              splitLines: rec.splitLines,
            ),
          );
          if (mounted) {
            navigator.pop();
          }
          if (widget.parentContext.mounted) {
            LifeOsTopToast.show(
              widget.parentContext,
              '✓ Đã lưu hóa đơn tách khoản (${VndAmount.format(rec.totalAmountMinor)})',
            );
          }
          return;

        case VoiceSentenceIntentKind.batchTransactions:
        case VoiceSentenceIntentKind.singleTransaction:
          for (final entry in finResult.personalEntries) {
            txActionBloc.add(
              TransactionCreateSubmitted(
                operationId: uuid.v4(),
                userId: widget.user.id,
                walletId: targetWalletId,
                categoryId: entry.categoryId,
                categoryName: entry.categoryName,
                kind: entry.kind,
                amountMinor: entry.amountMinor,
                merchant: entry.merchant,
                note: 'Xác nhận bằng Giọng nói AI',
                occurredAt: DateTime.now(),
              ),
            );
          }
          if (mounted) {
            navigator.pop();
          }
          if (widget.parentContext.mounted) {
            final count = finResult.personalEntries.length;
            final first = finResult.personalEntries.first;
            LifeOsTopToast.show(
              widget.parentContext,
              count == 1
                  ? '✓ Đã lưu: ${first.merchant} (${VndAmount.format(first.amountMinor)})'
                  : '✓ Đã xác nhận & lưu $count khoản thu chi!',
            );
          }
          return;
      }
    }

    // Path B: Cross-Domain LifeOS Spoken Intents (Calendar, Task, Water, Medication, Grocery)
    if (eval.omniDrafts.isNotEmpty) {
      if (mounted) {
        navigator.pop();
      }
      for (var i = 0; i < eval.omniDrafts.length; i++) {
        if (!widget.parentContext.mounted) break;
        await OmniActionExecutor.executeDraft(
          toastContext: widget.parentContext,
          draft: eval.omniDrafts[i],
          user: widget.user,
          walletId: targetWalletId,
          txActionBloc: txActionBloc,
          calBloc: calBloc,
          taskBloc: taskBloc,
          familyBloc: familyBloc,
          dailyBloc: dailyBloc,
          showSuccessToast: i == eval.omniDrafts.length - 1,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    final activeFamily = context.watch<FamilyBloc>().state.activeFamily;
    final knownMembers = activeFamily?.members ?? const <FamilyMemberInfo>[];

    final resolvedWalletId =
        _selectedWalletId != null &&
            wallets.any((w) => w.id == _selectedWalletId)
        ? _selectedWalletId!
        : (wallets.isNotEmpty ? wallets.first.id : 'wallet_cash_default');

    final eval = VoiceUtteranceEvaluator.evaluate(
      _textCtrl.text,
      currentUserId: widget.user.id,
      currentUserName: widget.user.fullName,
      knownMembers: knownMembers,
    );
    final analysis = eval.financialAnalysis;
    final hasOmniOnly = analysis == null && eval.omniDrafts.isNotEmpty;
    final hasAnyConfirmedDraft = analysis != null || hasOmniOnly;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSpokenText = _textCtrl.text.trim().isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Compact 3D Tactile Header (Airy, Bright, Human)
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: ShapeDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _isListening
                            ? const [Color(0xFF4ADE80), Color(0xFF16A34A)]
                            : const [Color(0xFF34D399), Color(0xFF0E8732)],
                      ),
                      shape: ContinuousRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.45),
                          width: 0.9,
                        ),
                      ),
                      shadows: [
                        BoxShadow(
                          color: const Color(0xFF16A34A).withValues(
                            alpha: isDark ? 0.30 : 0.22,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isListening
                          ? Icons.graphic_eq_rounded
                          : Icons.check_circle_outline_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isListening
                              ? 'Đang tự động thu âm...'
                              : (hasSpokenText
                                    ? 'Kiểm tra & Xác nhận lại'
                                    : 'Nói nhanh để ghi chép'),
                          softWrap: true,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          _isListening
                              ? 'Nói tự nhiên — tự dừng khi đủ ý để bạn duyệt lại'
                              : 'Thu chi, chia tiền, lịch hẹn, nhắc nước & thuốc',
                          softWrap: true,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_go_rounded, size: 16),
                    label: const Text('Dán'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 2. Bright, Airy 3D Porcelain-Mint Recording Card (Never Dark/Oppressive!)
              Container(
                key: const Key('voice_live_recording_card'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _isListening
                        ? (isDark
                              ? const [Color(0xFF283A31), Color(0xFF202E27)]
                              : const [Color(0xFFEFFBF4), Color(0xFFFFFFFF)])
                        : [c.surface, c.surfaceRaised],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isListening
                        ? c.primary.withValues(alpha: 0.42)
                        : (hasAnyConfirmedDraft
                              ? c.primary.withValues(alpha: 0.35)
                              : c.border),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.18 : 0.045,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.05 : 0.85,
                      ),
                      blurRadius: 0,
                      offset: const Offset(0, -1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          key: const Key('voice_mic_toggle_button'),
                          onTap: _toggleVoiceListening,
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: ShapeDecoration(
                              shape: ContinuousRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.48),
                                  width: 0.9,
                                ),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: _isListening
                                    ? const [
                                        Color(0xFF4ADE80),
                                        Color(0xFF16A34A),
                                      ]
                                    : [
                                        const Color(0xFF34D399),
                                        c.primary,
                                      ],
                              ),
                              shadows: [
                                BoxShadow(
                                  color: c.primary.withValues(alpha: 0.28),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              _isListening
                                  ? Icons.check_rounded
                                  : Icons.mic_rounded,
                              color: Colors.white,
                              size: 25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isListening
                                    ? eval.liveStatusVi
                                    : (hasSpokenText
                                          ? eval.confirmationBadgeVi
                                          : 'Chạm Mic để bắt đầu nói ngay'),
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: (_isListening || hasAnyConfirmedDraft)
                                      ? c.primary
                                      : c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 5),
                              if (_isListening)
                                SizedBox(
                                  height: 22,
                                  width: double.infinity,
                                  child: CustomPaint(
                                    painter: _VoiceWaveformPainter(
                                      isListening: _isListening,
                                      rmsDb: _rmsDb,
                                      activeColor: c.primary,
                                      idleColor: c.separator,
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  _voiceStatusHint ??
                                      (hasSpokenText
                                          ? 'Bạn có thể sửa câu bên dưới hoặc bấm Nói lại nếu chưa đúng.'
                                          : 'VD: "Ăn phở 55k", "Lẩu 450k chia 3 người", "Uống 300ml nước"'),
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: c.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_isListening && hasSpokenText) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: c.primary.withValues(
                            alpha: isDark ? 0.16 : 0.08,
                          ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          '“${_textCtrl.text}”',
                          softWrap: true,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 3. Editable Transcript Field (Always allows quick fix before confirming!)
              TextField(
                key: const Key('voice_transcript_input'),
                controller: _textCtrl,
                maxLines: 2,
                onChanged: (_) => setState(() => _awaitingConfirmation = true),
                decoration: InputDecoration(
                  labelText: 'Nội dung nhận diện (có thể sửa nhanh)',
                  hintText: 'VD: Ăn phở 55 nghìn và đổ xăng 70 nghìn',
                  suffixIcon: hasSpokenText
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: const Key('voice_retry_inline_button'),
                              tooltip: 'Xóa & thu âm lại',
                              onPressed: () =>
                                  _startListeningFresh(clearExisting: true),
                              icon: Icon(
                                Icons.mic_rounded,
                                size: 19,
                                color: c.primary,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Xóa nội dung',
                              onPressed: () {
                                _autoEndpointTimer?.cancel();
                                setState(() {
                                  _textCtrl.clear();
                                  _awaitingConfirmation = false;
                                  _voiceStatusHint = null;
                                });
                              },
                              icon: const Icon(Icons.clear_rounded, size: 18),
                            ),
                          ],
                        )
                      : null,
                ),
              ),

              if (!hasSpokenText && !_isListening) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _voiceExamples.map((ex) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            ex.chip,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          onPressed: () {
                            setState(() {
                              _textCtrl.text = ex.sentence;
                              _awaitingConfirmation = true;
                              _voiceStatusHint =
                                  'Mẫu câu sẵn sàng — bấm Xác nhận bên dưới để lưu.';
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // 4. Structured Confirmation Preview Card (`cho xác nhận lại`)
              if (hasAnyConfirmedDraft) ...[
                Container(
                  key: const Key('voice_confirmation_preview_card'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: c.primary.withValues(alpha: 0.38),
                      width: 1.1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 17,
                            color: c.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              analysis != null
                                  ? analysis.summaryHeadline
                                  : 'Sẽ thực hiện ${eval.omniDrafts.length} mục sau khi bạn xác nhận',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 12.8,
                                fontWeight: FontWeight.w800,
                                color: c.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 18),
                      if (analysis != null && analysis.groupSplit != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${analysis.groupSplit!.title} · ${analysis.groupSplit!.topic.displayLabel}',
                                softWrap: true,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              VndAmount.format(
                                analysis.groupSplit!.totalAmountMinor,
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: c.primary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...analysis.groupSplit!.shares.map((sh) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.person_outline_rounded,
                                        size: 16,
                                        color: c.secondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          sh.percentage != null
                                              ? '${sh.displayName} (${sh.percentage}%)'
                                              : sh.displayName,
                                          softWrap: true,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  VndAmount.format(sh.amountMinor),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 4),
                        Text(
                          activeFamily != null
                              ? 'Không gian nhận: ${activeFamily.name}'
                              : 'Sẽ tự khởi tạo "Nhóm Chia Tiền Nhanh" để lưu bảng chia',
                          softWrap: true,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ] else if (analysis != null &&
                          analysis.multiCategoryReceipt != null) ...[
                        ...analysis.multiCategoryReceipt!.splitLines.map((line) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                ProCategoryStyle.buildCategoryBadge(
                                  line.categoryName,
                                  size: 32,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    line.categoryName,
                                    softWrap: true,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  VndAmount.format(line.amountMinor),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ] else if (analysis != null) ...[
                        ...analysis.personalEntries.map((item) {
                          final isInc = item.kind == TransactionKind.income;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                ProCategoryStyle.buildCategoryBadge(
                                  item.categoryName,
                                  isCredit: isInc,
                                  size: 34,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.merchant,
                                        softWrap: true,
                                        style: const TextStyle(
                                          fontSize: 12.8,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        item.categoryName,
                                        softWrap: true,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  VndAmount.format(
                                    isInc
                                        ? item.amountMinor
                                        : -item.amountMinor,
                                    showPlus: true,
                                  ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: isInc ? c.success : c.textPrimary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ] else ...[
                        ...eval.omniDrafts.map((draft) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: c.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _iconForOmniKind(draft.kind),
                                    size: 17,
                                    color: c.primary,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    draft.summaryLineVi,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 12.8,
                                      fontWeight: FontWeight.w700,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      if (analysis != null &&
                          analysis.intentKind !=
                              VoiceSentenceIntentKind.groupBillSplit &&
                          wallets.length > 1) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey('voice_wallet_$resolvedWalletId'),
                          isExpanded: true,
                          initialValue: resolvedWalletId,
                          decoration: const InputDecoration(
                            labelText: 'Ví ghi nhận',
                            isDense: true,
                          ),
                          items: wallets
                              .map(
                                (w) => DropdownMenuItem(
                                  value: w.id,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(w.name),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _selectedWalletId = v);
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 5. Two-Action Confirmation Row: Nói lại | Xác nhận & Lưu
                Row(
                  children: [
                    OutlinedButton.icon(
                      key: const Key('voice_retry_bottom_button'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: () =>
                          _startListeningFresh(clearExisting: true),
                      icon: const Icon(Icons.mic_rounded, size: 18),
                      label: const Text('Nói lại'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('confirm_voice_analysis_button'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _isListening
                            ? null
                            : () => _confirmAndCommit(
                                context: context,
                                eval: eval,
                                targetWalletId: resolvedWalletId,
                                activeFamily: activeFamily,
                              ),
                        icon: const Icon(Icons.check_circle_rounded, size: 19),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            analysis?.intentKind ==
                                    VoiceSentenceIntentKind.groupBillSplit
                                ? 'Xác nhận chia (${analysis!.groupSplit!.shares.length} người)'
                                : 'Xác nhận & Lưu',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (analysis != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const Key('voice_open_financial_ai_review_btn'),
                    onPressed: () {
                      final transcript = _textCtrl.text.trim();
                      Navigator.of(context).pop();
                      widget.parentContext.push(
                        '/financial-ai',
                        extra: <String, dynamic>{
                          'initialText': transcript,
                          'initialSource': FinancialInputSource.voiceTranscript,
                        },
                      );
                    },
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: const Text('Mở trang chỉnh chi tiết từng khoản'),
                  ),
                ],
              ] else if (_awaitingConfirmation && hasSpokenText) ...[
                const SemanticStatusBadge(
                  kind: SemanticStatusKind.warning,
                  label:
                      'Chưa nhận diện được số tiền hoặc thời gian cụ thể. Bạn hãy bấm Nói lại hoặc gõ bổ sung số tiền nhé.',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('voice_retry_bottom_button'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        onPressed: () =>
                            _startListeningFresh(clearExisting: true),
                        icon: const Icon(Icons.mic_rounded, size: 18),
                        label: const Text('Nói lại ngay'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: const Key('voice_open_financial_ai_idle_btn'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                      ),
                      onPressed: () {
                        final transcript = _textCtrl.text.trim();
                        Navigator.of(context).pop();
                        widget.parentContext.push(
                          '/financial-ai',
                          extra: <String, dynamic>{
                            'initialText': transcript,
                            'initialSource':
                                FinancialInputSource.voiceTranscript,
                          },
                        );
                      },
                      icon: const Icon(Icons.tune_rounded, size: 17),
                      label: const Text('Chỉnh chi tiết'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  final bool isListening;
  final double rmsDb;
  final Color activeColor;
  final Color idleColor;

  const _VoiceWaveformPainter({
    required this.isListening,
    required this.rmsDb,
    required this.activeColor,
    required this.idleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 24;
    final spacing = size.width / barCount;
    final normRms = ((rmsDb + 2.0) / 12.0).clamp(0.18, 1.0);
    final paint = Paint()
      ..color = isListening ? activeColor : idleColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2;

    for (var i = 0; i < barCount; i++) {
      final x = i * spacing + spacing / 2;
      final wave = math.sin((i / barCount) * math.pi * 2.5).abs();
      final factor = isListening ? (0.25 + 0.75 * wave * normRms) : 0.22;
      final h = (size.height * factor).clamp(4.0, size.height);
      final y0 = (size.height - h) / 2;
      canvas.drawLine(Offset(x, y0), Offset(x, y0 + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) {
    return oldDelegate.isListening != isListening ||
        oldDelegate.rmsDb != rmsDb;
  }
}
