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
import 'lifeos_design_system.dart';
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
  late final TextEditingController _textCtrl;
  final String _voiceSessionToken = const Uuid().v4();
  final ValueNotifier<double> _rmsNotifier = ValueNotifier<double>(0.0);
  StreamSubscription<VoiceAssistantSignal>? _voiceSub;
  Timer? _autoEndpointTimer;
  Timer? _processingGuardTimer;
  DateTime? _lastVadRearmAt;
  bool _isListening = false;
  bool _isInitializingMic = false;
  bool _isRequestingPermission = false;
  bool _awaitingConfirmation = false;
  String _sessionPrefixText = '';
  VoiceEngineMode _selectedEngineMode = VoiceEngineMode.auto;
  VoiceDiagnosticsSnapshot? _diagnostics;
  String? _voiceStatusHint;
  String? _lastErrorCode;
  String? _selectedWalletId;

  static const double _kActiveSpeechRmsThresholdDb = 3.0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTranscript?.trim() ?? '';
    _textCtrl = TextEditingController(text: initial);
    _sessionPrefixText = initial;
    _awaitingConfirmation = initial.isNotEmpty;
    UserBehaviorPrefs.loadLastWalletId().then((savedId) {
      if (mounted && savedId != null && _selectedWalletId == null) {
        setState(() => _selectedWalletId = savedId);
      }
    });

    final bridge = sl<NativeVoiceAssistantBridge>();
    _voiceSub = bridge.watchSignals().listen(_handleVoiceSignal);
    _refreshDiagnostics();

    if (widget.autoStartListening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startListeningFresh();
      });
    }
  }

  Future<void> _refreshDiagnostics() async {
    final snap = await sl<NativeVoiceAssistantBridge>().getDiagnostics();
    if (mounted) {
      setState(() => _diagnostics = snap);
    }
  }

  @override
  void dispose() {
    _autoEndpointTimer?.cancel();
    _processingGuardTimer?.cancel();
    _voiceSub?.cancel();
    sl<NativeVoiceAssistantBridge>().cancelListening(
      sessionToken: _voiceSessionToken,
    );
    _rmsNotifier.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  List<FamilyMemberInfo> _currentKnownMembers() {
    if (!mounted) return const <FamilyMemberInfo>[];
    return context.read<FamilyBloc>().state.activeFamily?.members ??
        const <FamilyMemberInfo>[];
  }

  void _armProcessingSafetyGuard() {
    _processingGuardTimer?.cancel();
    _processingGuardTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted || !_isListening) return;
      setState(() {
        _isListening = false;
        _isInitializingMic = false;
        _rmsNotifier.value = 0.0;
        _awaitingConfirmation = _textCtrl.text.trim().isNotEmpty;
        if (_awaitingConfirmation) {
          _voiceStatusHint =
              'Đã chốt nội dung thu âm — mời bạn kiểm tra & xác nhận.';
        }
      });
    });
  }

  void _handleVoiceSignal(VoiceAssistantSignal sig) {
    if (!mounted) return;
    switch (sig) {
      case VoiceStateSignal(:final status):
        setState(() {
          if (status == 'requesting_permission') {
            _processingGuardTimer?.cancel();
            _isRequestingPermission = true;
            _isInitializingMic = false;
            _isListening = false;
            _rmsNotifier.value = 0.0;
            _lastErrorCode = null;
            _voiceStatusHint =
                'Vui lòng bấm Cho phép quyền Micro trên hộp thoại hệ thống...';
          } else if (status == 'initializing') {
            _processingGuardTimer?.cancel();
            _isRequestingPermission = false;
            _isInitializingMic = true;
            _isListening = true;
            _awaitingConfirmation = false;
            _lastErrorCode = null;
            _voiceStatusHint = 'Đang mở kênh Micro tiếng Việt...';
          } else if (status == 'listening') {
            final wasInitializing = _isInitializingMic;
            _processingGuardTimer?.cancel();
            _isRequestingPermission = false;
            _isInitializingMic = false;
            _isListening = true;
            _awaitingConfirmation = false;
            _lastErrorCode = null;
            _voiceStatusHint = null;
            if (wasInitializing) {
              HapticFeedback.selectionClick();
            }
          } else if (status == 'processing') {
            _isRequestingPermission = false;
            _isInitializingMic = false;
            _voiceStatusHint = 'Đang chốt câu vừa nói...';
            _armProcessingSafetyGuard();
          } else if (status == 'idle') {
            _processingGuardTimer?.cancel();
            _isRequestingPermission = false;
            _isInitializingMic = false;
            _isListening = false;
            _rmsNotifier.value = 0.0;
            if (_textCtrl.text.trim().isNotEmpty) {
              _awaitingConfirmation = true;
            }
          }
        });
        if (status == 'listening' || status == 'idle') {
          _refreshDiagnostics();
        }
      case VoiceRmsSignal(:final rmsDb):
        _rmsNotifier.value = rmsDb;
        // Acoustic Voice Activity Guard: never auto-stop while the user's voice
        // is actively producing speech energy above the room noise floor!
        if (_isListening &&
            rmsDb >= _kActiveSpeechRmsThresholdDb &&
            _autoEndpointTimer != null &&
            _autoEndpointTimer!.isActive) {
          final now = DateTime.now();
          if (_lastVadRearmAt == null ||
              now.difference(_lastVadRearmAt!).inMilliseconds >= 180) {
            _lastVadRearmAt = now;
            final currentText = _textCtrl.text.trim();
            if (currentText.isNotEmpty) {
              _scheduleSmartAutoEndpoint(currentText);
            }
          }
        }
      case VoiceTranscriptSignal(:final text, :final isFinal):
        _processingGuardTimer?.cancel();
        final cleanSegment = text.trim();
        final combined = cleanSegment.isEmpty
            ? _sessionPrefixText
            : NativeVoiceAssistantBridge.combinePrefixAndSegment(
                _sessionPrefixText,
                text,
              );
        final cleanCombined = combined.trim();
        setState(() {
          _isRequestingPermission = false;
          _isInitializingMic = false;
          _lastErrorCode = null;
          if (combined.isNotEmpty || cleanSegment.isNotEmpty) {
            _textCtrl.text = combined;
            _textCtrl.selection = TextSelection.collapsed(
              offset: combined.length,
            );
          }
          if (isFinal) {
            _autoEndpointTimer?.cancel();
            _isListening = false;
            _rmsNotifier.value = 0.0;
            _sessionPrefixText = cleanCombined;
            _awaitingConfirmation = cleanCombined.isNotEmpty;
            _voiceStatusHint = cleanCombined.isNotEmpty
                ? 'Đã tự động ngắt thu âm — kiểm tra & bấm Xác nhận bên dưới.'
                : null;
          }
        });
        if (isFinal) {
          if (cleanCombined.isNotEmpty) {
            HapticFeedback.mediumImpact();
          }
        } else if (cleanCombined.isNotEmpty) {
          _scheduleSmartAutoEndpoint(cleanCombined);
        }
      case VoiceErrorSignal(:final message, :final code):
        _autoEndpointTimer?.cancel();
        _processingGuardTimer?.cancel();
        _rmsNotifier.value = 0.0;
        setState(() {
          _isRequestingPermission = false;
          _isInitializingMic = false;
          _isListening = false;
          if (_textCtrl.text.trim().isNotEmpty) {
            _sessionPrefixText = _textCtrl.text.trim();
            _lastErrorCode = null;
            _awaitingConfirmation = true;
            _voiceStatusHint =
                'Đã giữ lại nội dung vừa nghe — mời bạn kiểm tra & xác nhận.';
          } else {
            _lastErrorCode = code;
            _voiceStatusHint = message;
          }
        });
        _refreshDiagnostics();
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
      _processingGuardTimer?.cancel();
      HapticFeedback.mediumImpact();
      _rmsNotifier.value = 0.0;
      setState(() {
        _isListening = false;
        _isInitializingMic = false;
        _sessionPrefixText = _textCtrl.text.trim();
        _awaitingConfirmation = _textCtrl.text.trim().isNotEmpty;
        _voiceStatusHint = eval.isReadyComplete
            ? 'Đã nhận diện đủ ý và tự dừng — mời bạn xác nhận.'
            : 'Đã tạm dừng thu âm — kiểm tra lại nội dung trước khi lưu.';
      });
    });
  }

  Future<void> _startListeningFresh({
    bool clearExisting = false,
    bool preferSystemDialog = false,
    VoiceEngineMode? overrideMode,
  }) async {
    _autoEndpointTimer?.cancel();
    _processingGuardTimer?.cancel();
    final bridge = sl<NativeVoiceAssistantBridge>();
    if (overrideMode != null) {
      _selectedEngineMode = overrideMode;
    }
    if (clearExisting) {
      _textCtrl.clear();
      _sessionPrefixText = '';
    } else {
      _sessionPrefixText = _textCtrl.text.trim();
    }
    final useDialog =
        preferSystemDialog ||
        _selectedEngineMode == VoiceEngineMode.systemDialog;
    _rmsNotifier.value = 0.0;
    setState(() {
      _isListening = true;
      _isInitializingMic = false;
      _isRequestingPermission = false;
      _awaitingConfirmation = false;
      _lastErrorCode = null;
      _voiceStatusHint = null;
    });
    final res = await bridge.startListening(
      sessionToken: _voiceSessionToken,
      preferSystemDialog: useDialog,
      engineMode: useDialog
          ? VoiceEngineMode.systemDialog
          : _selectedEngineMode,
    );
    if (!mounted) return;
    if (res == 'PERMISSION_REQUESTED') {
      setState(() {
        _isListening = false;
        _isInitializingMic = false;
        _isRequestingPermission = true;
        _voiceStatusHint =
            'Vui lòng bấm Cho phép quyền Micro trên hộp thoại hệ thống...';
      });
    } else if (res == 'UNSUPPORTED' || res == 'ERROR') {
      setState(() {
        _isListening = false;
        _isInitializingMic = false;
        _isRequestingPermission = false;
        _lastErrorCode = res;
        _voiceStatusHint =
            'Thiết bị chưa bật dịch vụ thu âm — vui lòng nhập trực tiếp nội dung bên dưới.';
      });
    }
  }

  Future<void> _toggleVoiceListening() async {
    final bridge = sl<NativeVoiceAssistantBridge>();
    if (_isListening) {
      _autoEndpointTimer?.cancel();
      _processingGuardTimer?.cancel();
      await bridge.stopListening();
      if (mounted) {
        HapticFeedback.lightImpact();
        _rmsNotifier.value = 0.0;
        setState(() {
          _isListening = false;
          _isInitializingMic = false;
          _sessionPrefixText = _textCtrl.text.trim();
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
    final motion = LifeOsMotionScope.of(context);

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
                        RepaintBoundary(
                          child: SizedBox(
                            width: 58,
                            height: 58,
                            child: ValueListenableBuilder<double>(
                              valueListenable: _rmsNotifier,
                              builder: (context, rmsDb, micChild) {
                                return CustomPaint(
                                  painter: _VoiceMicHaloPainter(
                                    isListening: _isListening,
                                    isReducedMotion: motion.isReducedMotion,
                                    rmsDb: rmsDb,
                                    color: c.primary,
                                  ),
                                  child: micChild,
                                );
                              },
                              child: Center(
                                child: GestureDetector(
                                  key: const Key('voice_mic_toggle_button'),
                                  onTap: _toggleVoiceListening,
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: ShapeDecoration(
                                      shape: ContinuousRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                        side: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: 0.48,
                                          ),
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
                                          color: c.primary.withValues(
                                            alpha: 0.28,
                                          ),
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
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isListening
                                    ? (_isInitializingMic
                                          ? 'Đang mở kênh Micro tiếng Việt...'
                                          : eval.liveStatusVi)
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
                                RepaintBoundary(
                                  child: SizedBox(
                                    height: 22,
                                    width: double.infinity,
                                    child: ValueListenableBuilder<double>(
                                      valueListenable: _rmsNotifier,
                                      builder: (context, rmsDb, _) {
                                        return CustomPaint(
                                          painter: _VoiceWaveformPainter(
                                            isListening: _isListening,
                                            rmsDb: motion.isReducedMotion
                                                ? -2.0
                                                : rmsDb,
                                            activeColor: c.primary,
                                            idleColor: c.separator,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  _voiceStatusHint ??
                                      (hasSpokenText
                                          ? 'Có thể sửa nhanh bên dưới hoặc bấm Nói lại.'
                                          : 'Hỗ trợ nói gộp nhiều khoản thu chi, chia nhóm, lịch hẹn & uống nước'),
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: c.textSecondary,
                                  ),
                                ),
                              if (!_isListening &&
                                  !_isRequestingPermission &&
                                  !hasSpokenText &&
                                  _lastErrorCode != null) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if (_lastErrorCode == 'PERMISSION_DENIED' ||
                                        _lastErrorCode ==
                                            'PERMISSION_PERMANENTLY_DENIED')
                                      FilledButton.tonalIcon(
                                        key: const Key(
                                          'voice_grant_mic_permission_btn',
                                        ),
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        onPressed: () async {
                                          if (_lastErrorCode ==
                                              'PERMISSION_PERMANENTLY_DENIED') {
                                            await sl<
                                                  NativeVoiceAssistantBridge
                                                >()
                                                .openMicrophoneSettings();
                                          } else {
                                            await _startListeningFresh();
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.mic_external_on_rounded,
                                          size: 15,
                                        ),
                                        label: Text(
                                          _lastErrorCode ==
                                                  'PERMISSION_PERMANENTLY_DENIED'
                                              ? 'Mở Cài đặt Micro'
                                              : 'Cấp quyền Micro',
                                          style: const TextStyle(fontSize: 11.5),
                                        ),
                                      ),
                                    OutlinedButton.icon(
                                      key: const Key(
                                        'voice_system_dialog_fallback_btn',
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () => _startListeningFresh(
                                        preferSystemDialog: true,
                                      ),
                                      icon: const Icon(
                                        Icons.record_voice_over_outlined,
                                        size: 15,
                                      ),
                                      label: const Text(
                                        'Thu âm hệ thống',
                                        style: TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
                onChanged: (val) {
                  setState(() {
                    _awaitingConfirmation = true;
                    if (!_isListening) {
                      _sessionPrefixText = val.trim();
                    }
                  });
                },
                decoration: InputDecoration(
                  labelText: 'Nội dung nhận diện (có thể sửa nhanh)',
                  hintText: 'Nhập hoặc nói nội dung cần ghi...',
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
                                  _sessionPrefixText = '';
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
              const SizedBox(height: 8),

              // 3b. Progressive Disclosure: Mic Mode & Diagnostics ("Chi tiết" — zero clutter by default!)
              LifeOsDetailsDiscloseSection(
                toggleKey: const Key('voice_mic_details_toggle'),
                label: 'Chi tiết thu âm',
                expandedLabel: 'Thu gọn chi tiết',
                child: Container(
                  key: const Key('voice_mic_diagnostics_panel'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chế độ kênh thu âm tiếng Việt',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: VoiceEngineMode.values.map((mode) {
                          final selected = _selectedEngineMode == mode;
                          return ChoiceChip(
                            key: Key('voice_engine_chip_${mode.wireValue}'),
                            label: Text(
                              mode.labelVi,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            selected: selected,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) {
                              _startListeningFresh(
                                clearExisting: false,
                                preferSystemDialog:
                                    mode == VoiceEngineMode.systemDialog,
                                overrideMode: mode,
                              );
                            },
                          );
                        }).toList(),
                      ),
                      if (_diagnostics != null) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            LifeOsStatusPill(
                              icon: _diagnostics!.hasRecordPermission
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.warning_amber_rounded,
                              label: _diagnostics!.hasRecordPermission
                                  ? 'Quyền Micro: Đã cấp'
                                  : 'Quyền Micro: Chưa cấp',
                              tone: _diagnostics!.hasRecordPermission
                                  ? LifeOsAccentTone.emerald
                                  : LifeOsAccentTone.amber,
                            ),
                            LifeOsStatusPill(
                              icon: Icons.graphic_eq_rounded,
                              label: _diagnostics!.readableEngineSummaryVi,
                              tone: LifeOsAccentTone.blue,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

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
        (oldDelegate.rmsDb - rmsDb).abs() > 0.05;
  }
}

class _VoiceMicHaloPainter extends CustomPainter {
  final bool isListening;
  final bool isReducedMotion;
  final double rmsDb;
  final Color color;

  const _VoiceMicHaloPainter({
    required this.isListening,
    required this.isReducedMotion,
    required this.rmsDb,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isListening) return;
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = math.min(size.width, size.height) * 0.42;

    if (isReducedMotion) {
      canvas.drawCircle(
        center,
        baseRadius + 2.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.28),
      );
      return;
    }

    final norm = ((rmsDb + 2.0) / 12.0).clamp(0.0, 1.0);
    final outerRadius = baseRadius + 2.5 + (norm * 5.0);
    final innerRadius = baseRadius + 1.2 + (norm * 2.6);

    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.10 + (0.14 * norm)),
    );
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: 0.24 + (0.28 * norm)),
    );
  }

  @override
  bool shouldRepaint(covariant _VoiceMicHaloPainter oldDelegate) {
    if (oldDelegate.isListening != isListening ||
        oldDelegate.isReducedMotion != isReducedMotion ||
        oldDelegate.color != color) {
      return true;
    }
    if (!isListening || isReducedMotion) return false;
    return (oldDelegate.rmsDb - rmsDb).abs() > 0.05;
  }
}
