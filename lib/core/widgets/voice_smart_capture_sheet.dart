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
import '../../features/budgets/presentation/bloc/budget_bloc.dart';
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
import '../../features/transactions/presentation/bloc/transaction_state.dart';
import '../../features/vehicles/presentation/bloc/vehicle_bloc.dart';
import '../constants/app_assets.dart';
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
  final budgetBloc = _tryReadBloc<BudgetBloc>(context);
  final vehicleBloc = _tryReadBloc<VehicleBloc>(context);

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
          if (budgetBloc != null)
            BlocProvider<BudgetBloc>.value(value: budgetBloc),
          if (vehicleBloc != null)
            BlocProvider<VehicleBloc>.value(value: vehicleBloc),
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
  bool _isSubmittingConfirm = false;
  String _batchSignature = '';
  final Map<int, String> _batchOperationIds = <int, String>{};
  final Set<int> _completedBatchIndices = <int>{};
  final Map<String, String> _participantOverrides = <String, String>{};
  final Set<int> _dismissedPersonalIndices = <int>{};
  final Set<int> _dismissedOmniIndices = <int>{};
  bool _multiCatMismatchConfirmed = false;
  String _sessionPrefixText = '';
  VoiceEngineMode _selectedEngineMode = VoiceEngineMode.googleService;
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
    _selectedEngineMode = VoiceEngineMode.fromWireValue(
      UserBehaviorPrefs.cachedVoiceEngineMode,
    );
    UserBehaviorPrefs.loadLastWalletId().then((savedId) {
      if (mounted && savedId != null && _selectedWalletId == null) {
        setState(() => _selectedWalletId = savedId);
      }
    });

    final bridge = sl<NativeVoiceAssistantBridge>();
    _voiceSub = bridge.watchSignals().listen(_handleVoiceSignal);
    _refreshDiagnostics();

    UserBehaviorPrefs.loadPreferredVoiceEngineMode().then((savedWire) {
      if (!mounted) return;
      final loadedMode = VoiceEngineMode.fromWireValue(savedWire);
      if (loadedMode != _selectedEngineMode) {
        setState(() => _selectedEngineMode = loadedMode);
      }
      if (widget.autoStartListening) {
        _startListeningFresh();
      }
    });
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
      case VoiceEngineSwitchedSignal(:final modeWireValue):
        final nextMode = VoiceEngineMode.fromWireValue(modeWireValue);
        unawaited(UserBehaviorPrefs.savePreferredVoiceEngineMode(nextMode.wireValue));
        setState(() {
          _selectedEngineMode = nextMode;
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
    bool forceInlineProbe = false,
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
      _participantOverrides.clear();
      _dismissedPersonalIndices.clear();
      _dismissedOmniIndices.clear();
      _multiCatMismatchConfirmed = false;
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
      forceInlineProbe: forceInlineProbe,
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
    required List<WalletEntity> wallets,
  }) async {
    if (_isSubmittingConfirm) return;
    final finResult = eval.financialAnalysis;
    if (finResult?.groupSplit != null && !finResult!.groupSplit!.isValid) {
      LifeOsTopToast.show(
        context,
        finResult.groupSplit!.validationMessageVi ??
            'Bảng chia tiền chưa hợp lệ — vui lòng kiểm tra lại.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }
    if (finResult?.multiCategoryReceipt?.validationStatus ==
            SplitValidationStatus.requiresConfirmation &&
        !_multiCatMismatchConfirmed) {
      LifeOsTopToast.show(
        context,
        'Vui lòng tích xác nhận chênh lệch tổng hóa đơn trước khi lưu.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }

    setState(() => _isSubmittingConfirm = true);

    const uuid = Uuid();
    final navigator = Navigator.of(context);
    final txActionBloc = context.read<TransactionActionBloc>();
    final familyBloc = context.read<FamilyBloc>();
    final calBloc = _tryReadBloc<CalendarBloc>(context);
    final taskBloc = _tryReadBloc<TaskBloc>(context);
    final dailyBloc = _tryReadBloc<DailyLifeBloc>(context);
    final budgetBloc = _tryReadBloc<BudgetBloc>(context);
    final vehicleBloc = _tryReadBloc<VehicleBloc>(context);

    final currentSig = '${_textCtrl.text.trim()}::$targetWalletId';
    if (_batchSignature != currentSig) {
      _batchSignature = currentSig;
      _batchOperationIds.clear();
      _completedBatchIndices.clear();
    }

    var savedFinancialSummary = '';
    var savedSingleTxId = '';
    var savedSingleMerchant = '';

    try {
      // Path A: Rich Financial / Group Split / Multi-Category Receipt
      if (finResult != null) {
        switch (finResult.intentKind) {
          case VoiceSentenceIntentKind.groupBillSplit:
            final split = finResult.groupSplit!;
            var targetFamilyId = activeFamily?.id;
            if (targetFamilyId == null) {
              final createWaiter = familyBloc.stream
                  .firstWhere(
                    (s) =>
                        !s.isSubmitting &&
                        (s.activeFamily != null || s.failure != null),
                  )
                  .timeout(
                    const Duration(seconds: 6),
                    onTimeout: () => familyBloc.state,
                  );
              familyBloc.add(
                FamilyCreateSubmitted(
                  userId: widget.user.id,
                  userName: widget.user.fullName,
                  familyName: 'Nhóm Chia Tiền Nhanh',
                  spaceType: CollaborationSpaceType.group,
                ),
              );
              final nextFamState = await createWaiter;
              targetFamilyId = nextFamState.activeFamily?.id;
            }
            if (targetFamilyId == null) {
              if (context.mounted) {
                LifeOsTopToast.show(
                  context,
                  'Chưa thể khởi tạo nhóm chia tiền — vui lòng thử lại.',
                  kind: LifeOsToastKind.warning,
                );
              }
              return;
            }
            final splitWaiter = familyBloc.stream
                .firstWhere(
                  (s) =>
                      !s.isSubmitting &&
                      (s.message != null || s.failure != null),
                )
                .timeout(
                  const Duration(seconds: 8),
                  onTimeout: () => familyBloc.state,
                );
            familyBloc.add(
              SharedBillSplitCreated(
                CreateSharedBillSplitParams(
                  familyId: targetFamilyId,
                  title: split.title,
                  topic: split.topic,
                  paidByUserId: split.paidByParticipantId ?? widget.user.id,
                  paidByName: split.paidByDisplayName ?? widget.user.fullName,
                  totalAmountMinor: split.totalAmountMinor,
                  splitMethod: split.splitMethod,
                  participantIds: split.shares
                      .map((s) => s.participantId)
                      .toList(),
                  participantNames: {
                    for (final s in split.shares)
                      s.participantId: s.displayName,
                  },
                  rawInputValuesByUserId: split.rawInputValuesByUserId,
                  choreOrTaskNote: 'Xác nhận từ Giọng nói AI',
                ),
              ),
            );
            final splitState = await splitWaiter;
            if (splitState.failure != null || splitState.message == null) {
              if (context.mounted) {
                LifeOsTopToast.show(
                  context,
                  splitState.failure?.message ??
                      'Không thể lưu khoản chia hóa đơn — vui lòng thử lại.',
                  kind: LifeOsToastKind.error,
                );
              }
              return;
            }
            await UserBehaviorPrefs.rememberWallet(targetWalletId);
            savedFinancialSummary =
                '✓ Đã chia hóa đơn "${split.title}" (${VndAmount.format(split.totalAmountMinor)}) cho ${split.shares.length} người!';
            break;

          case VoiceSentenceIntentKind.multiCategoryReceipt:
            final rec = finResult.multiCategoryReceipt!;
            final sumLines = rec.splitLines.fold<int>(
              0,
              (s, l) => s + l.amountMinor,
            );
            final effectiveTotal = math.max(rec.totalAmountMinor, sumLines);
            final opId = _batchOperationIds.putIfAbsent(0, () => uuid.v4());
            final outcome = await txActionBloc.submitAndAwaitCreate(
              TransactionCreateSubmitted(
                operationId: opId,
                userId: widget.user.id,
                walletId: targetWalletId,
                categoryName: rec.splitLines.first.categoryName,
                kind: TransactionKind.expense,
                amountMinor: effectiveTotal,
                merchant: rec.merchant,
                note: 'Tách khoản bằng Giọng nói AI',
                occurredAt: DateTime.now(),
                splitLines: rec.splitLines,
              ),
            );
            if (outcome.status != ActionStatus.success ||
                outcome.lastCreatedTransaction == null) {
              if (context.mounted) {
                LifeOsTopToast.show(
                  context,
                  outcome.failure?.message ??
                      'Không thể lưu hóa đơn tách khoản — vui lòng thử lại.',
                  kind: LifeOsToastKind.error,
                );
              }
              return;
            }
            await UserBehaviorPrefs.rememberWallet(targetWalletId);
            savedFinancialSummary =
                '✓ Đã lưu hóa đơn tách khoản (${VndAmount.format(effectiveTotal)})';
            break;

          case VoiceSentenceIntentKind.batchTransactions:
          case VoiceSentenceIntentKind.singleTransaction:
            final entries = finResult.personalEntries;
            final activeEntryIndices = <int>[
              for (var i = 0; i < entries.length; i++)
                if (!_dismissedPersonalIndices.contains(i)) i,
            ];
            final failedItems = <({String merchant, String? reason})>[];
            TransactionEntity? singleCreatedTx;

            for (final i in activeEntryIndices) {
              if (_completedBatchIndices.contains(i)) {
                continue;
              }
              final entry = entries[i];
              final opId = _batchOperationIds.putIfAbsent(i, () => uuid.v4());
              final outcome = await txActionBloc.submitAndAwaitCreate(
                TransactionCreateSubmitted(
                  operationId: opId,
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
              if (outcome.status == ActionStatus.success &&
                  outcome.lastCreatedTransaction != null) {
                _completedBatchIndices.add(i);
                singleCreatedTx = outcome.lastCreatedTransaction;
                savedSingleMerchant = entry.merchant;
              } else {
                failedItems.add((
                  merchant: entry.merchant,
                  reason: outcome.failure?.message,
                ));
              }
            }

            if (failedItems.isNotEmpty) {
              final savedCount = _completedBatchIndices.length;
              final firstFail = failedItems.first;
              if (mounted) {
                setState(() {
                  _voiceStatusHint = activeEntryIndices.length == 1
                      ? (firstFail.reason ??
                            'Chưa thể lưu giao dịch — bấm Xác nhận & Lưu để thử lại.')
                      : 'Đã lưu $savedCount/${activeEntryIndices.length} khoản. Khoản "${firstFail.merchant}" gặp lỗi — bấm Xác nhận & Lưu để thử lại phần lỗi mà không tạo trùng.';
                });
              }
              if (context.mounted) {
                LifeOsTopToast.show(
                  context,
                  activeEntryIndices.length == 1
                      ? (firstFail.reason ??
                            'Không thể lưu giao dịch "${firstFail.merchant}" — vui lòng thử lại.')
                      : 'Đã lưu $savedCount/${activeEntryIndices.length} khoản — "${firstFail.merchant}" gặp lỗi. Bấm thử lại sẽ không bị trùng khoản đã lưu.',
                  kind: LifeOsToastKind.error,
                );
              }
              return;
            }

            if (activeEntryIndices.isNotEmpty) {
              await UserBehaviorPrefs.rememberWallet(targetWalletId);
              if (activeEntryIndices.length == 1 && singleCreatedTx != null) {
                savedSingleTxId = singleCreatedTx.id;
                final onlyEntry = entries[activeEntryIndices.single];
                savedFinancialSummary =
                    '✓ Đã lưu: ${onlyEntry.merchant} (${VndAmount.format(onlyEntry.amountMinor)})';
              } else {
                savedFinancialSummary =
                    '✓ Đã xác nhận & lưu ${activeEntryIndices.length} khoản thu chi!';
              }
            }
            break;
        }
      }

      // Path B: Execute Cross-Domain Omni Drafts!
      // IMPORTANT: Never swallow non-financial calendar/task/reminder drafts when Path A succeeded!
      final omniToRun = finResult != null
          ? eval.nonFinancialOmniDrafts
          : eval.omniDrafts;
      final activeOmniIndices = <int>[
        for (var i = 0; i < omniToRun.length; i++)
          if (!_dismissedOmniIndices.contains(i)) i,
      ];

      var omniExecutedCount = 0;
      OmniActionDraft? lastExecutedOmni;
      if (activeOmniIndices.isNotEmpty) {
        var failedCount = 0;
        for (final i in activeOmniIndices) {
          final offsetKey = 1000 + i;
          if (_completedBatchIndices.contains(offsetKey)) continue;
          if (!context.mounted) break;
          final ok = await OmniActionExecutor.executeDraft(
            toastContext: context,
            draft: omniToRun[i],
            user: widget.user,
            walletId: targetWalletId,
            availableWallets: wallets,
            txActionBloc: txActionBloc,
            calBloc: calBloc,
            taskBloc: taskBloc,
            familyBloc: familyBloc,
            dailyBloc: dailyBloc,
            budgetBloc: budgetBloc,
            vehicleBloc: vehicleBloc,
            showSuccessToast: false,
          );
          if (ok) {
            _completedBatchIndices.add(offsetKey);
            omniExecutedCount++;
            lastExecutedOmni = omniToRun[i];
          } else {
            failedCount++;
          }
        }
        if (failedCount > 0) {
          return;
        }
      }

      _batchOperationIds.clear();
      _completedBatchIndices.clear();
      if (mounted) {
        navigator.pop();
      }
      if (widget.parentContext.mounted) {
        if (savedFinancialSummary.isNotEmpty && omniExecutedCount > 0) {
          LifeOsTopToast.show(
            widget.parentContext,
            '$savedFinancialSummary & Đã thêm $omniExecutedCount lịch/nhắc việc!',
          );
        } else if (savedSingleTxId.isNotEmpty) {
          LifeOsTopToast.show(
            widget.parentContext,
            savedFinancialSummary,
            actionLabel: 'Hoàn tác',
            onAction: () {
              txActionBloc.add(
                TransactionReverseRequested(
                  userId: widget.user.id,
                  transactionId: savedSingleTxId,
                  reason: 'Hoàn tác giao dịch "$savedSingleMerchant"',
                ),
              );
            },
          );
        } else if (savedFinancialSummary.isNotEmpty) {
          LifeOsTopToast.show(widget.parentContext, savedFinancialSummary);
        } else if (omniExecutedCount > 0) {
          LifeOsTopToast.show(
            widget.parentContext,
            omniExecutedCount == 1 && lastExecutedOmni != null
                ? '✓ Đã lưu: ${lastExecutedOmni.summaryLineVi}'
                : '✓ Đã thực hiện & lưu $omniExecutedCount thao tác thông minh!',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingConfirm = false);
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
      explicitParticipantOverrides: _participantOverrides,
    );
    final analysis = eval.financialAnalysis;
    final visiblePersonalCount = analysis == null
        ? 0
        : analysis.personalEntries.length - _dismissedPersonalIndices.length;
    final trailingOmniDrafts = analysis != null
        ? eval.nonFinancialOmniDrafts
        : eval.omniDrafts;
    final visibleOmniCount =
        trailingOmniDrafts.length - _dismissedOmniIndices.length;
    final hasAnyConfirmedDraft = analysis != null || eval.omniDrafts.isNotEmpty;
    final isGroupSplitInvalid =
        analysis?.groupSplit != null && !analysis!.groupSplit!.isValid;
    final isReceiptNeedsConfirm =
        analysis?.multiCategoryReceipt?.validationStatus ==
            SplitValidationStatus.requiresConfirmation &&
        !_multiCatMismatchConfirmed;
    final isEverythingDismissed =
        analysis != null &&
        analysis.groupSplit == null &&
        analysis.multiCategoryReceipt == null &&
        visiblePersonalCount <= 0 &&
        visibleOmniCount <= 0;
    final isOmniOnlyDismissed = analysis == null && visibleOmniCount <= 0;
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
                  BananaGlassIcon(
                    assetPath: AppAssets.ic3dVoiceAi,
                    fallbackIcon: _isListening
                        ? Icons.graphic_eq_rounded
                        : Icons.mic_rounded,
                    size: 42,
                    borderRadius: 13,
                    isSelected: _isListening,
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
                    key: const Key('voice_quick_google_dialog_btn'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () async {
                      await UserBehaviorPrefs.savePreferredVoiceEngineMode(
                        VoiceEngineMode.systemDialog.wireValue,
                      );
                      if (!mounted) return;
                      await _startListeningFresh(
                        preferSystemDialog: true,
                        overrideMode: VoiceEngineMode.systemDialog,
                      );
                    },
                    icon: const Icon(Icons.record_voice_over_outlined, size: 15),
                    label: const Text('Google', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_go_rounded, size: 15),
                    label: const Text('Dán', style: TextStyle(fontSize: 12)),
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
                    _participantOverrides.clear();
                    _dismissedPersonalIndices.clear();
                    _dismissedOmniIndices.clear();
                    _multiCatMismatchConfirmed = false;
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
                                  _participantOverrides.clear();
                                  _dismissedPersonalIndices.clear();
                                  _dismissedOmniIndices.clear();
                                  _multiCatMismatchConfirmed = false;
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
                        'Kênh thu âm Google Tiếng Việt',
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
                        children: VoiceEngineMode.selectableGoogleModes.map((
                          mode,
                        ) {
                          final selected = _selectedEngineMode == mode;
                          return ChoiceChip(
                            key: Key('voice_engine_chip_${mode.wireValue}'),
                            label: Text(
                              mode.labelVi,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            selected: selected,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) async {
                              await UserBehaviorPrefs
                                  .savePreferredVoiceEngineMode(mode.wireValue);
                              if (!mounted) return;
                              await _startListeningFresh(
                                clearExisting: false,
                                preferSystemDialog:
                                    mode == VoiceEngineMode.systemDialog,
                                overrideMode: mode,
                                forceInlineProbe:
                                    mode == VoiceEngineMode.googleService,
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
              if (eval.blockedClauses.isNotEmpty && !hasAnyConfirmedDraft) ...[
                Container(
                  key: const Key('voice_blocked_safety_banner'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: c.warning.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, size: 18, color: c.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Đã bỏ qua (không tạo giao dịch): ${eval.blockedClauses.map((b) => '"${b.clause}" (${b.reasonVi})').join(' · ')}',
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
                const SizedBox(height: 10),
              ],
              if (hasAnyConfirmedDraft) ...[
                Container(
                  key: const Key('voice_confirmation_preview_card'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: (isGroupSplitInvalid ? c.error : c.primary)
                          .withValues(alpha: 0.45),
                      width: 1.1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isGroupSplitInvalid
                                ? Icons.error_outline_rounded
                                : Icons.verified_rounded,
                            size: 17,
                            color: isGroupSplitInvalid ? c.error : c.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              analysis != null
                                  ? analysis.summaryHeadline
                                  : 'Sẽ thực hiện $visibleOmniCount mục sau khi bạn xác nhận',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 12.8,
                                fontWeight: FontWeight.w800,
                                color:
                                    isGroupSplitInvalid ? c.error : c.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 18),
                      if (analysis != null && analysis.groupSplit != null) ...[
                        if (!analysis.groupSplit!.isValid) ...[
                          Container(
                            key: const Key('voice_split_validation_warning'),
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: c.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: c.error.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 18,
                                      color: c.error,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        analysis.groupSplit!.validationMessageVi ??
                                            'Bảng chia tiền chưa hợp lệ — vui lòng sửa lại câu nói.',
                                        softWrap: true,
                                        style: TextStyle(
                                          fontSize: 12.2,
                                          fontWeight: FontWeight.w700,
                                          color: c.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (analysis
                                    .groupSplit!
                                    .ambiguousParticipants
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  ...analysis.groupSplit!.ambiguousParticipants.map((
                                    amb,
                                  ) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Chọn đúng người cho "${amb.spokenName}":',
                                            softWrap: true,
                                            style: TextStyle(
                                              fontSize: 11.8,
                                              fontWeight: FontWeight.w700,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: amb.ambiguousCandidates
                                                .map((cand) {
                                              final isChosen =
                                                  _participantOverrides[amb
                                                          .spokenName] ==
                                                      cand.participantId;
                                              return ChoiceChip(
                                                key: Key(
                                                  'voice_disambiguate_${cand.participantId}',
                                                ),
                                                label: Text(
                                                  cand.displayName,
                                                ),
                                                selected: isChosen,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .padded,
                                                onSelected: (_) {
                                                  setState(() {
                                                    _participantOverrides[amb
                                                            .spokenName] =
                                                        cand.participantId;
                                                  });
                                                },
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ],
                            ),
                          ),
                        ],
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
                                              : sh.sharesWeight != null
                                              ? '${sh.displayName} (${sh.sharesWeight} phần)'
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
                        if (analysis.multiCategoryReceipt!.validationStatus ==
                            SplitValidationStatus.requiresConfirmation) ...[
                          Container(
                            key: const Key('voice_receipt_mismatch_warning'),
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: c.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: c.warning.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  analysis
                                          .multiCategoryReceipt!
                                          .validationMessageVi ??
                                      'Tổng các dòng tách vượt tổng hóa đơn gốc.',
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 12.2,
                                    fontWeight: FontWeight.w700,
                                    color: c.textPrimary,
                                  ),
                                ),
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  value: _multiCatMismatchConfirmed,
                                  title: const Text(
                                    'Xác nhận cập nhật theo tổng các dòng tách',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  onChanged: (v) {
                                    setState(
                                      () => _multiCatMismatchConfirmed =
                                          v ?? false,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
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
                        ...analysis.personalEntries.asMap().entries.where(
                          (e) => !_dismissedPersonalIndices.contains(e.key),
                        ).map((mapEntry) {
                          final idx = mapEntry.key;
                          final item = mapEntry.value;
                          final isInc = item.kind == TransactionKind.income;
                          final allowDismiss =
                              visiblePersonalCount + visibleOmniCount > 1;
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
                                if (allowDismiss)
                                  IconButton(
                                    key: Key('voice_remove_tx_$idx'),
                                    tooltip: 'Bỏ khoản này',
                                    constraints: const BoxConstraints(
                                      minWidth: 48,
                                      minHeight: 48,
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _dismissedPersonalIndices.add(idx),
                                      );
                                    },
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: c.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                      if (trailingOmniDrafts.isNotEmpty) ...[
                        ...trailingOmniDrafts.asMap().entries.where(
                          (e) => !_dismissedOmniIndices.contains(e.key),
                        ).map((mapEntry) {
                          final idx = mapEntry.key;
                          final draft = mapEntry.value;
                          final allowDismiss =
                              (analysis != null
                                  ? visiblePersonalCount
                                  : 0) +
                              visibleOmniCount >
                              1;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              children: [
                                LifeOsIconSquircle(
                                  icon: _iconForOmniKind(draft.kind),
                                  size: 34,
                                  iconSize: 17,
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
                                if (allowDismiss)
                                  IconButton(
                                    key: Key('voice_remove_omni_$idx'),
                                    tooltip: 'Bỏ mục này',
                                    constraints: const BoxConstraints(
                                      minWidth: 48,
                                      minHeight: 48,
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _dismissedOmniIndices.add(idx),
                                      );
                                    },
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: c.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                      if (eval.blockedClauses.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Đã tự động bỏ qua: ${eval.blockedClauses.map((b) => '"${b.clause}"').join(', ')}',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 11.2,
                            color: c.textSecondary,
                          ),
                        ),
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
                        onPressed:
                            (_isListening ||
                                    _isSubmittingConfirm ||
                                    isGroupSplitInvalid ||
                                    isReceiptNeedsConfirm ||
                                    isEverythingDismissed ||
                                    isOmniOnlyDismissed)
                                ? null
                                : () => _confirmAndCommit(
                                    context: context,
                                    eval: eval,
                                    targetWalletId: resolvedWalletId,
                                    activeFamily: activeFamily,
                                    wallets: wallets,
                                  ),
                        icon: Icon(
                          _isSubmittingConfirm
                              ? Icons.hourglass_top_rounded
                              : isGroupSplitInvalid
                                  ? Icons.block_rounded
                                  : Icons.check_circle_rounded,
                          size: 19,
                        ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _isSubmittingConfirm
                                ? 'Đang lưu...'
                                : isGroupSplitInvalid
                                    ? 'Cần sửa lỗi chia tiền'
                                    : analysis?.intentKind ==
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
