import 'dart:async';
import 'dart:io';
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
import '../../features/voice_assistant/data/datasources/local_asr_model_manager.dart';
import '../../features/voice_assistant/data/datasources/voice_native_channel_datasource.dart';
import '../../features/voice_assistant/data/engines/android_on_device_engine.dart';
import '../../features/voice_assistant/data/engines/android_speech_engine.dart';
import '../../features/voice_assistant/data/engines/local_asr_engine.dart';
import '../../features/voice_assistant/data/engines/system_dialog_engine.dart';
import '../../features/voice_assistant/data/repositories/voice_capability_repository_impl.dart';
import '../../features/voice_assistant/domain/entities/voice_engine_capability.dart';
import '../../features/voice_assistant/domain/entities/voice_session.dart';
import '../../features/voice_assistant/domain/services/endpoint_policy.dart';
import '../../features/voice_assistant/domain/services/speech_engine_adapter.dart';
import '../../features/voice_assistant/domain/services/voice_session_coordinator.dart';
import '../../features/voice_assistant/presentation/bloc/voice_assistant_bloc.dart';
import '../../features/voice_assistant/presentation/bloc/voice_assistant_event.dart';
import '../../features/voice_assistant/presentation/bloc/voice_assistant_state.dart';
import '../../features/voice_assistant/presentation/widgets/voice_live_waveform.dart';
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

bool _isVoiceCaptureSheetOpen = false;

T? _tryReadBloc<T extends StateStreamableSource<Object?>>(BuildContext ctx) {
  try {
    return ctx.read<T>();
  } catch (_) {
    return null;
  }
}

VoiceAssistantBloc _createFallbackVoiceAssistantBloc() {
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
  return VoiceAssistantBloc(
    coordinator: coordinator,
    modelRepository: modelRepo,
    disposeCoordinatorOnClose: true,
  );
}

Future<void> showVoiceSmartCaptureSheet(
  BuildContext context, {
  bool? autoStartListening,
  String? initialTranscript,
}) async {
  if (_isVoiceCaptureSheetOpen) return;
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
  final existingVoiceBloc = _tryReadBloc<VoiceAssistantBloc>(context);
  final ownsLocalVoiceBloc = existingVoiceBloc == null;
  final voiceBloc =
      existingVoiceBloc ??
      (sl.isRegistered<VoiceAssistantBloc>()
          ? sl<VoiceAssistantBloc>()
          : _createFallbackVoiceAssistantBloc());

  final hasPrefilledText =
      initialTranscript != null && initialTranscript.trim().isNotEmpty;
  final effectiveAutoStart = autoStartListening ?? !hasPrefilledText;

  _isVoiceCaptureSheetOpen = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return MultiBlocProvider(
          providers: [
            BlocProvider<TransactionListBloc>.value(value: txListBloc),
            BlocProvider<TransactionActionBloc>.value(value: txActionBloc),
            BlocProvider<FamilyBloc>.value(value: familyBloc),
            BlocProvider<VoiceAssistantBloc>.value(value: voiceBloc),
            if (calBloc != null)
              BlocProvider<CalendarBloc>.value(value: calBloc),
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
  } finally {
    _isVoiceCaptureSheetOpen = false;
    if (ownsLocalVoiceBloc) {
      await voiceBloc.close();
    }
  }
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
    extends State<_VoiceSmartCaptureSheetBody>
    with WidgetsBindingObserver {
  late final TextEditingController _textCtrl;
  late final VoiceAssistantBloc _voiceBloc;
  final String _ownerId = 'voice_sheet_${const Uuid().v4()}';
  Timer? _tapDebounceTimer;
  bool _userInteractedBeforeHydrate = false;
  bool _isSubmittingConfirm = false;
  String _batchSignature = '';
  final Map<int, String> _batchOperationIds = <int, String>{};
  final Set<int> _completedBatchIndices = <int>{};
  final Map<String, String> _participantOverrides = <String, String>{};
  final Set<int> _dismissedPersonalIndices = <int>{};
  final Set<int> _dismissedOmniIndices = <int>{};
  bool _multiCatMismatchConfirmed = false;
  String? _selectedWalletId;
  String? _localPasteHint;

  static const int _kRapidTapDebounceMs = 250;

  bool _consumeRapidTapDebounce() {
    if (_tapDebounceTimer?.isActive ?? false) {
      return false;
    }
    _tapDebounceTimer = Timer(
      const Duration(milliseconds: _kRapidTapDebounceMs),
      () {},
    );
    return true;
  }

  VoiceRecognitionPreference _preferenceFromWire(String wire) {
    if (wire == VoiceRecognitionPreference.offlineStrict.wireValue ||
        wire == VoiceEngineMode.onDevice.wireValue) {
      return VoiceRecognitionPreference.offlineStrict;
    }
    if (wire == VoiceRecognitionPreference.systemDialog.wireValue ||
        wire == VoiceEngineMode.systemDialog.wireValue) {
      return VoiceRecognitionPreference.systemDialog;
    }
    if (wire == VoiceRecognitionPreference.hybridAuto.wireValue) {
      return VoiceRecognitionPreference.hybridAuto;
    }
    return VoiceRecognitionPreference.onlineGoogle;
  }

  String _wireFromPreference(VoiceRecognitionPreference pref) {
    return switch (pref) {
      VoiceRecognitionPreference.offlineStrict =>
        VoiceRecognitionPreference.offlineStrict.wireValue,
      VoiceRecognitionPreference.systemDialog =>
        VoiceEngineMode.systemDialog.wireValue,
      VoiceRecognitionPreference.hybridAuto =>
        VoiceRecognitionPreference.hybridAuto.wireValue,
      VoiceRecognitionPreference.onlineGoogle =>
        VoiceEngineMode.googleService.wireValue,
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voiceBloc = context.read<VoiceAssistantBloc>();

    final initial = widget.initialTranscript?.trim() ?? '';
    _textCtrl = TextEditingController(text: initial);

    UserBehaviorPrefs.loadLastWalletId().then((savedId) {
      if (mounted && savedId != null && _selectedWalletId == null) {
        setState(() => _selectedWalletId = savedId);
      }
    });

    _voiceBloc.add(const VoiceAssistantInitialized());
    if (initial.isNotEmpty) {
      _voiceBloc
        ..add(const VoiceResetToIdleRequested(clearTranscript: true))
        ..add(VoiceTranscriptEdited(initial));
    } else {
      _voiceBloc.add(const VoiceResetToIdleRequested(clearTranscript: true));
    }

    UserBehaviorPrefs.loadPreferredVoiceEngineMode().then((savedWire) {
      if (!mounted || _userInteractedBeforeHydrate) return;
      final loadedPref = _preferenceFromWire(savedWire);
      _voiceBloc.add(VoicePreferenceChanged(loadedPref));
      if (widget.autoStartListening) {
        _startListeningFresh(clearExisting: true, overridePref: loadedPref);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _voiceBloc.isClosed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _voiceBloc.add(const VoiceAppLifecycleChanged(true));
    } else if (state == AppLifecycleState.resumed) {
      _voiceBloc.add(const VoiceAppLifecycleChanged(false));
    }
  }

  @override
  void dispose() {
    _isVoiceCaptureSheetOpen = false;
    _tapDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (!_voiceBloc.isClosed) {
      final currentSession = _voiceBloc.state.session;
      if (currentSession.ownerId == _ownerId &&
          currentSession.sessionId.isNotEmpty &&
          currentSession.phase.isActiveCapture) {
        _voiceBloc.add(
          VoiceCancelRequested(
            sessionId: currentSession.sessionId,
            reason: 'sheet_disposed',
          ),
        );
      }
    }
    _textCtrl.dispose();
    super.dispose();
  }

  void _startListeningFresh({
    bool clearExisting = false,
    VoiceRecognitionPreference? overridePref,
  }) {
    _userInteractedBeforeHydrate = true;
    _localPasteHint = null;
    if (clearExisting) {
      setState(() {
        _textCtrl.clear();
        _participantOverrides.clear();
        _dismissedPersonalIndices.clear();
        _dismissedOmniIndices.clear();
        _multiCatMismatchConfirmed = false;
      });
    }
    final pref = overridePref ?? _voiceBloc.state.activePreference;
    _voiceBloc.add(
      VoiceStartRequested(
        ownerId: _ownerId,
        entryPoint: VoiceEntryPoint.voiceSheet,
        preference: pref,
        clearTranscript: clearExisting,
      ),
    );
  }

  void _toggleVoiceListening(VoiceAssistantState voiceState) {
    if (!_consumeRapidTapDebounce()) return;
    _userInteractedBeforeHydrate = true;
    final phase = voiceState.phase;
    if (phase == VoiceSessionPhase.finalizing) {
      // VOICE-001: never start or force-close while finalizing in-flight audio!
      return;
    }
    if (phase == VoiceSessionPhase.listening) {
      HapticFeedback.lightImpact();
      _voiceBloc.add(
        VoiceStopRequested(sessionId: voiceState.session.sessionId),
      );
      return;
    }
    if (phase == VoiceSessionPhase.preparing ||
        phase == VoiceSessionPhase.requestingPermission) {
      _voiceBloc.add(
        VoiceCancelRequested(
          sessionId: voiceState.session.sessionId,
          reason: 'user_cancelled_before_ready',
        ),
      );
      return;
    }
    _startListeningFresh(clearExisting: false);
  }

  Future<void> _pasteFromClipboard() async {
    _userInteractedBeforeHydrate = true;
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = clip?.text?.trim() ?? '';
    if (txt.isEmpty) {
      if (mounted) {
        setState(() => _localPasteHint = 'Bộ nhớ tạm hiện đang trống.');
      }
      return;
    }
    setState(() {
      _textCtrl.text = txt;
      _textCtrl.selection = TextSelection.collapsed(offset: txt.length);
      _localPasteHint = 'Đã đọc nội dung từ bộ nhớ tạm — mời bạn xác nhận!';
    });
    _voiceBloc.add(VoiceTranscriptEdited(txt));
  }

  String _headlineForPhase(VoiceSessionPhase phase, bool hasSpokenText) {
    return switch (phase) {
      VoiceSessionPhase.requestingPermission => 'Đang chờ cấp quyền Micro...',
      VoiceSessionPhase.preparing => 'Đang chuẩn bị Micro...',
      VoiceSessionPhase.listening => 'Đang nghe tiếng Việt...',
      VoiceSessionPhase.finalizing => 'Đang xử lý câu nói...',
      VoiceSessionPhase.submitting => 'Đang lưu dữ liệu...',
      VoiceSessionPhase.review => 'Kiểm tra & Xác nhận lại',
      VoiceSessionPhase.completed => 'Đã hoàn tất',
      VoiceSessionPhase.error =>
        hasSpokenText ? 'Kiểm tra & Xác nhận lại' : 'Thu âm tạm gián đoạn',
      VoiceSessionPhase.cancelled =>
        hasSpokenText ? 'Kiểm tra & Xác nhận lại' : 'Đã hủy phiên thu âm',
      VoiceSessionPhase.idle =>
        hasSpokenText ? 'Kiểm tra & Xác nhận lại' : 'Nói nhanh để ghi chép',
    };
  }

  String _subtitleForPhase(VoiceAssistantState voiceState) {
    return switch (voiceState.phase) {
      VoiceSessionPhase.requestingPermission =>
        'Vui lòng bấm Cho phép trên hộp thoại hệ thống',
      VoiceSessionPhase.preparing => 'Đang kết nối bộ nhận diện giọng nói...',
      VoiceSessionPhase.listening =>
        voiceState.endpointMode == VoiceEndpointMode.explicitStopOnly
            ? 'Nói tự nhiên — bấm Dừng khi hoàn tất để tránh cắt giữa câu'
            : 'Nói tự nhiên — chế độ tự dừng thông minh đang bật',
      VoiceSessionPhase.finalizing =>
        'Đang chờ kết quả cuối cùng từ bộ nhận diện...',
      _ => 'Thu chi, chia tiền, lịch hẹn, nhắc nước & thuốc',
    };
  }

  String _cardStatusTitle(
    VoiceAssistantState voiceState,
    VoiceUtteranceEvaluation eval,
    bool hasSpokenText,
  ) {
    return switch (voiceState.phase) {
      VoiceSessionPhase.requestingPermission => 'Đang chờ cấp quyền Micro...',
      VoiceSessionPhase.preparing => 'Đang mở kênh Micro tiếng Việt...',
      VoiceSessionPhase.listening =>
        hasSpokenText ? eval.liveStatusVi : 'Đang thu âm... Hãy nói tự nhiên',
      VoiceSessionPhase.finalizing =>
        'Đang xử lý & hoàn tất câu nói — vui lòng đợi giây lát...',
      VoiceSessionPhase.error =>
        voiceState.session.lastErrorMessageVi ??
            voiceState.session.lastErrorKind?.friendlyMessageVi ??
            'Không nghe rõ câu nói — bạn có thể bấm Nói lại hoặc nhập bên dưới.',
      _ =>
        hasSpokenText
            ? eval.confirmationBadgeVi
            : 'Chạm Mic để bắt đầu nói ngay',
    };
  }

  String _readableEngineSummary(VoiceAssistantState voiceState) {
    final diag = voiceState.diagnostics;
    final activeEngine = voiceState.session.engineId;
    if (activeEngine == VoiceEngineId.androidOnDevice) {
      return 'Nhận diện Offline trên máy';
    }
    if (activeEngine == VoiceEngineId.localAsr) {
      return 'Local ASR Offline (trên máy)';
    }
    if (activeEngine == VoiceEngineId.systemDialog) {
      return 'Hộp thoại giọng nói hệ thống';
    }
    if (diag.availableEngines.any((e) => e.startsWith('service:com.google.'))) {
      return 'Speech Services by Google';
    }
    if (diag.availableEngines.contains('system_default')) {
      return 'Kênh hệ thống Android';
    }
    return diag.availableEngines.isNotEmpty
        ? diag.availableEngines.first
        : 'Kênh mặc định hệ thống';
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
    _voiceBloc.add(const VoiceSubmitStarted());

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
                  _localPasteHint = activeEntryIndices.length == 1
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
        _voiceBloc.add(const VoiceSubmitCompleted());
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
        if (_voiceBloc.state.phase == VoiceSessionPhase.submitting) {
          _voiceBloc.add(const VoiceSubmitReverted());
        }
        setState(() => _isSubmittingConfirm = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VoiceAssistantBloc, VoiceAssistantState>(
      listener: (context, voiceState) {
        if (voiceState.session.ownerId == _ownerId ||
            voiceState.session.ownerId.isEmpty) {
          final nextText = voiceState.effectiveText;
          if (nextText != _textCtrl.text &&
              (voiceState.phase.isActiveCapture ||
                  voiceState.phase == VoiceSessionPhase.review)) {
            _textCtrl.text = nextText;
            _textCtrl.selection = TextSelection.collapsed(
              offset: nextText.length,
            );
          }
          if (voiceState.phase == VoiceSessionPhase.review &&
              nextText.isNotEmpty) {
            HapticFeedback.mediumImpact();
          }
        }
      },
      builder: (context, voiceState) {
        final c = TammySemanticColors.of(context);
        final wallets = context.watch<TransactionListBloc>().state.wallets;
        final activeFamily = context.watch<FamilyBloc>().state.activeFamily;
        final knownMembers =
            activeFamily?.members ?? const <FamilyMemberInfo>[];

        final resolvedWalletId =
            _selectedWalletId != null &&
                wallets.any((w) => w.id == _selectedWalletId)
            ? _selectedWalletId!
            : (wallets.isNotEmpty ? wallets.first.id : 'wallet_cash_default');

        final phase = voiceState.phase;
        final isActiveCapture = phase.isActiveCapture;
        final isFinalizing = phase == VoiceSessionPhase.finalizing;
        final isListening = phase == VoiceSessionPhase.listening;
        final isRequestingPerm =
            phase == VoiceSessionPhase.requestingPermission;
        final isReview = phase == VoiceSessionPhase.review;
        final errorKind = voiceState.session.lastErrorKind;
        final isPermError =
            errorKind == VoiceErrorKind.permissionDenied ||
            errorKind == VoiceErrorKind.permissionPermanentlyDenied;
        final isPermPermanentlyDenied =
            errorKind == VoiceErrorKind.permissionPermanentlyDenied;
        final isOfflineStrict =
            voiceState.activePreference ==
            VoiceRecognitionPreference.offlineStrict;

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
            : analysis.personalEntries.length -
                  _dismissedPersonalIndices.length;
        final trailingOmniDrafts = analysis != null
            ? eval.nonFinancialOmniDrafts
            : eval.omniDrafts;
        final visibleOmniCount =
            trailingOmniDrafts.length - _dismissedOmniIndices.length;
        final hasAnyConfirmedDraft =
            analysis != null || eval.omniDrafts.isNotEmpty;
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
                  // 1. Compact Header
                  Row(
                    children: [
                      BananaGlassIcon(
                        assetPath: AppAssets.ic3dVoiceAi,
                        fallbackIcon: isActiveCapture
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_rounded,
                        size: 42,
                        borderRadius: 13,
                        isSelected: isActiveCapture,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _headlineForPhase(phase, hasSpokenText),
                              softWrap: true,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              _subtitleForPhase(voiceState),
                              softWrap: true,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      if (!isOfflineStrict)
                        TextButton.icon(
                          key: const Key('voice_quick_google_dialog_btn'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: isFinalizing
                              ? null
                              : () async {
                                  if (!_consumeRapidTapDebounce()) return;
                                  await UserBehaviorPrefs.savePreferredVoiceEngineMode(
                                    VoiceEngineMode.systemDialog.wireValue,
                                  );
                                  if (!mounted) return;
                                  _voiceBloc.add(
                                    const VoicePreferenceChanged(
                                      VoiceRecognitionPreference.systemDialog,
                                    ),
                                  );
                                  _startListeningFresh(
                                    overridePref:
                                        VoiceRecognitionPreference.systemDialog,
                                  );
                                },
                          icon: const Icon(
                            Icons.record_voice_over_outlined,
                            size: 15,
                          ),
                          label: const Text(
                            'Google',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(
                          Icons.content_paste_go_rounded,
                          size: 15,
                        ),
                        label: const Text(
                          'Dán',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 2. Voice Engine 2.0 Truthful Recording Card
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
                        colors: isActiveCapture
                            ? (isDark
                                  ? const [Color(0xFF283A31), Color(0xFF202E27)]
                                  : const [
                                      Color(0xFFEFFBF4),
                                      Color(0xFFFFFFFF),
                                    ])
                            : [c.surface, c.surfaceRaised],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isActiveCapture
                            ? c.primary.withValues(alpha: 0.42)
                            : (phase == VoiceSessionPhase.error
                                  ? c.error.withValues(alpha: 0.45)
                                  : (hasAnyConfirmedDraft
                                        ? c.primary.withValues(alpha: 0.35)
                                        : c.border)),
                        width: 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              key: const Key('voice_mic_toggle_button'),
                              onTap: () => _toggleVoiceListening(voiceState),
                              child: Container(
                                width: 52,
                                height: 52,
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
                                    colors: isFinalizing
                                        ? [c.warning, c.warning]
                                        : isListening
                                        ? const [
                                            Color(0xFFEF4444),
                                            Color(0xFFDC2626),
                                          ]
                                        : [const Color(0xFF34D399), c.primary],
                                  ),
                                ),
                                child: Icon(
                                  isFinalizing
                                      ? Icons.hourglass_top_rounded
                                      : isListening
                                      ? Icons.stop_rounded
                                      : Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _cardStatusTitle(
                                      voiceState,
                                      eval,
                                      hasSpokenText,
                                    ),
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: phase == VoiceSessionPhase.error
                                          ? c.error
                                          : (isActiveCapture ||
                                                    hasAnyConfirmedDraft
                                                ? c.primary
                                                : c.textPrimary),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (isActiveCapture) ...[
                                    VoiceLiveWaveform(
                                      sample: voiceState.waveform,
                                      phase: phase,
                                      accentColor: c.primary,
                                      height: 24,
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        if (isListening)
                                          FilledButton.tonalIcon(
                                            key: const Key(
                                              'voice_stop_session_btn',
                                            ),
                                            style: FilledButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            onPressed: () =>
                                                _toggleVoiceListening(
                                                  voiceState,
                                                ),
                                            icon: const Icon(
                                              Icons.stop_circle_outlined,
                                              size: 16,
                                            ),
                                            label: const Text('Dừng'),
                                          ),
                                        OutlinedButton.icon(
                                          key: const Key(
                                            'voice_cancel_session_btn',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          onPressed: () {
                                            _voiceBloc.add(
                                              VoiceCancelRequested(
                                                sessionId: voiceState
                                                    .session
                                                    .sessionId,
                                                reason: 'user_cancelled',
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 16,
                                          ),
                                          label: const Text('Hủy'),
                                        ),
                                      ],
                                    ),
                                  ] else
                                    Text(
                                      _localPasteHint ??
                                          voiceState.actionableHintVi ??
                                          (hasSpokenText
                                              ? 'Có thể sửa nhanh bên dưới, bấm Mic để nói tiếp hoặc Nói lại.'
                                              : 'Hỗ trợ nói gộp nhiều khoản thu chi, chia nhóm, lịch hẹn & uống nước'),
                                      softWrap: true,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  if (!isActiveCapture &&
                                      !isRequestingPerm &&
                                      (phase == VoiceSessionPhase.error ||
                                          errorKind != null)) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        if (isPermError)
                                          FilledButton.tonalIcon(
                                            key: const Key(
                                              'voice_grant_mic_permission_btn',
                                            ),
                                            style: FilledButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            onPressed: () async {
                                              if (isPermPermanentlyDenied) {
                                                await sl<
                                                      NativeVoiceAssistantBridge
                                                    >()
                                                    .openMicrophoneSettings();
                                              } else {
                                                _startListeningFresh();
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.mic_external_on_rounded,
                                              size: 15,
                                            ),
                                            label: Text(
                                              isPermPermanentlyDenied
                                                  ? 'Mở Cài đặt Micro'
                                                  : 'Cấp quyền Micro',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ),
                                        if (!isOfflineStrict)
                                          OutlinedButton.icon(
                                            key: const Key(
                                              'voice_system_dialog_fallback_btn',
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            onPressed: () {
                                              if (!_consumeRapidTapDebounce()) {
                                                return;
                                              }
                                              _voiceBloc.add(
                                                const VoicePreferenceChanged(
                                                  VoiceRecognitionPreference
                                                      .systemDialog,
                                                ),
                                              );
                                              _startListeningFresh(
                                                overridePref:
                                                    VoiceRecognitionPreference
                                                        .systemDialog,
                                              );
                                            },
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
                        if (isActiveCapture && hasSpokenText) ...[
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

                  // 3. Editable Transcript Field (Always editable, disabled overwrite while finalizing!)
                  TextField(
                    key: const Key('voice_transcript_input'),
                    controller: _textCtrl,
                    maxLines: 2,
                    onChanged: (val) {
                      _userInteractedBeforeHydrate = true;
                      setState(() {
                        _participantOverrides.clear();
                        _dismissedPersonalIndices.clear();
                        _dismissedOmniIndices.clear();
                        _multiCatMismatchConfirmed = false;
                      });
                      if (isActiveCapture && !isFinalizing) {
                        _voiceBloc.add(
                          VoiceCancelRequested(
                            sessionId: voiceState.session.sessionId,
                            reason: 'user_typed_manually',
                          ),
                        );
                      }
                      if (!isFinalizing) {
                        _voiceBloc.add(VoiceTranscriptEdited(val));
                      }
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
                                  onPressed: isFinalizing
                                      ? null
                                      : () {
                                          if (!_consumeRapidTapDebounce()) {
                                            return;
                                          }
                                          _startListeningFresh(
                                            clearExisting: true,
                                          );
                                        },
                                  icon: Icon(
                                    Icons.mic_rounded,
                                    size: 19,
                                    color: c.primary,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Xóa nội dung',
                                  onPressed: isFinalizing
                                      ? null
                                      : () {
                                          setState(() {
                                            _textCtrl.clear();
                                            _participantOverrides.clear();
                                            _dismissedPersonalIndices.clear();
                                            _dismissedOmniIndices.clear();
                                            _multiCatMismatchConfirmed = false;
                                            _localPasteHint = null;
                                          });
                                          _voiceBloc.add(
                                            const VoiceResetToIdleRequested(
                                              clearTranscript: true,
                                            ),
                                          );
                                        },
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                  ),
                                ),
                              ],
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 3b. Progressive Disclosure: Offline/Online Mode, Auto-Endpoint Opt-in & Diagnostics
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
                            'Chế độ nhận diện giọng nói (Offline / Online)',
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
                            children:
                                const <(VoiceRecognitionPreference, String, String)>[
                                  (
                                    VoiceRecognitionPreference.onlineGoogle,
                                    'google_service',
                                    'Google Speech (Trực tiếp)',
                                  ),
                                  (
                                    VoiceRecognitionPreference.systemDialog,
                                    'system_dialog',
                                    'Hộp thoại Google',
                                  ),
                                  (
                                    VoiceRecognitionPreference.offlineStrict,
                                    'offline_strict',
                                    'Chỉ Offline',
                                  ),
                                ].map((entry) {
                                  final (pref, chipSuffix, label) = entry;
                                  final selected =
                                      voiceState.activePreference == pref;
                                  return ChoiceChip(
                                    key: Key('voice_engine_chip_$chipSuffix'),
                                    label: Text(
                                      label,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    selected: selected,
                                    visualDensity: VisualDensity.compact,
                                    onSelected: isFinalizing
                                        ? null
                                        : (_) async {
                                            if (!_consumeRapidTapDebounce()) {
                                              return;
                                            }
                                            await UserBehaviorPrefs.savePreferredVoiceEngineMode(
                                              _wireFromPreference(pref),
                                            );
                                            if (!mounted) return;
                                            _voiceBloc.add(
                                              VoicePreferenceChanged(pref),
                                            );
                                            _startListeningFresh(
                                              clearExisting: false,
                                              overridePref: pref,
                                            );
                                          },
                                  );
                                }).toList(),
                          ),
                          const SizedBox(height: 6),
                          Material(
                            type: MaterialType.transparency,
                            child: SwitchListTile.adaptive(
                              key: const Key('voice_auto_endpoint_toggle'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Tự dừng thông minh sau khoảng nghỉ',
                                style: TextStyle(fontSize: 12),
                              ),
                              subtitle: const Text(
                                'Mặc định tắt (bấm Dừng chủ động để tránh cắt câu dài).',
                                style: TextStyle(fontSize: 11),
                              ),
                              value:
                                  voiceState.endpointMode ==
                                  VoiceEndpointMode.smartAutoEndpoint,
                              onChanged: (enabled) {
                                _voiceBloc.add(
                                  VoiceEndpointModeChanged(
                                    enabled
                                        ? VoiceEndpointMode.smartAutoEndpoint
                                        : VoiceEndpointMode.explicitStopOnly,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              LifeOsStatusPill(
                                icon: voiceState.diagnostics.hasMicPermission
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.warning_amber_rounded,
                                label: voiceState.diagnostics.hasMicPermission
                                    ? 'Quyền Micro: Đã cấp'
                                    : 'Quyền Micro: Chưa cấp',
                                tone: voiceState.diagnostics.hasMicPermission
                                    ? LifeOsAccentTone.emerald
                                    : LifeOsAccentTone.amber,
                              ),
                              LifeOsStatusPill(
                                icon: Icons.graphic_eq_rounded,
                                label: _readableEngineSummary(voiceState),
                                tone: LifeOsAccentTone.blue,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const Key('voice_open_diagnostics_btn'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                              ),
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.parentContext.push('/voice-diagnostics');
                              },
                              icon: const Icon(
                                Icons.monitor_heart_outlined,
                                size: 16,
                              ),
                              label: const Text(
                                'Chẩn đoán, Kiểm tra Micro & Mô hình Offline',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 4. Structured Confirmation Preview Card (`cho xác nhận lại`)
                  if (eval.blockedClauses.isNotEmpty &&
                      !hasAnyConfirmedDraft) ...[
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
                          Icon(
                            Icons.shield_outlined,
                            size: 18,
                            color: c.warning,
                          ),
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
                                color: isGroupSplitInvalid
                                    ? c.error
                                    : c.primary,
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
                                    color: isGroupSplitInvalid
                                        ? c.error
                                        : c.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          if (analysis != null &&
                              analysis.groupSplit != null) ...[
                            if (!analysis.groupSplit!.isValid) ...[
                              Container(
                                key: const Key(
                                  'voice_split_validation_warning',
                                ),
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
                                            analysis
                                                    .groupSplit!
                                                    .validationMessageVi ??
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
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
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
                                                children: amb.ambiguousCandidates.map((
                                                  cand,
                                                ) {
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                            if (analysis
                                    .multiCategoryReceipt!
                                    .validationStatus ==
                                SplitValidationStatus.requiresConfirmation) ...[
                              Container(
                                key: const Key(
                                  'voice_receipt_mismatch_warning',
                                ),
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
                            ...analysis.multiCategoryReceipt!.splitLines.map((
                              line,
                            ) {
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
                            ...analysis.personalEntries
                                .asMap()
                                .entries
                                .where(
                                  (e) => !_dismissedPersonalIndices.contains(
                                    e.key,
                                  ),
                                )
                                .map((mapEntry) {
                                  final idx = mapEntry.key;
                                  final item = mapEntry.value;
                                  final isInc =
                                      item.kind == TransactionKind.income;
                                  final allowDismiss =
                                      visiblePersonalCount + visibleOmniCount >
                                      1;
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
                                            color: isInc
                                                ? c.success
                                                : c.textPrimary,
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
                                                () => _dismissedPersonalIndices
                                                    .add(idx),
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
                            ...trailingOmniDrafts
                                .asMap()
                                .entries
                                .where(
                                  (e) => !_dismissedOmniIndices.contains(e.key),
                                )
                                .map((mapEntry) {
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
                                                () => _dismissedOmniIndices.add(
                                                  idx,
                                                ),
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
                          onPressed: isFinalizing
                              ? null
                              : () {
                                  if (!_consumeRapidTapDebounce()) return;
                                  _startListeningFresh(clearExisting: true);
                                },
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
                                (isActiveCapture ||
                                    isRequestingPerm ||
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
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
                              'initialSource':
                                  FinancialInputSource.voiceTranscript,
                            },
                          );
                        },
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: const Text('Mở trang chỉnh chi tiết từng khoản'),
                      ),
                    ],
                  ] else if (isReview && hasSpokenText) ...[
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
                            onPressed: isFinalizing
                                ? null
                                : () {
                                    if (!_consumeRapidTapDebounce()) return;
                                    _startListeningFresh(clearExisting: true);
                                  },
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
      },
    );
  }
}
