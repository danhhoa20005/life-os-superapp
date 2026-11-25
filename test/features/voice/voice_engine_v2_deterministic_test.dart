import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/features/voice_assistant/data/datasources/local_asr_model_manager.dart';
import 'package:life_os/features/voice_assistant/data/datasources/voice_native_channel_datasource.dart';
import 'package:life_os/features/voice_assistant/data/engines/android_speech_engine.dart';
import 'package:life_os/features/voice_assistant/data/engines/local_asr_engine.dart';
import 'package:life_os/features/voice_assistant/data/engines/system_dialog_engine.dart';
import 'package:life_os/features/voice_assistant/data/repositories/voice_capability_repository_impl.dart';
import 'package:life_os/features/voice_assistant/domain/entities/voice_engine_capability.dart';
import 'package:life_os/features/voice_assistant/domain/entities/voice_event.dart';
import 'package:life_os/features/voice_assistant/domain/entities/voice_model_package.dart';
import 'package:life_os/features/voice_assistant/domain/entities/voice_session.dart';
import 'package:life_os/features/voice_assistant/domain/repositories/local_asr_model_repository.dart';
import 'package:life_os/features/voice_assistant/domain/services/endpoint_policy.dart';
import 'package:life_os/features/voice_assistant/domain/services/engine_selection_policy.dart';
import 'package:life_os/features/voice_assistant/domain/services/monotonic_clock.dart';
import 'package:life_os/features/voice_assistant/domain/services/speech_engine_adapter.dart';
import 'package:life_os/features/voice_assistant/domain/services/voice_activity_detector.dart';
import 'package:life_os/features/voice_assistant/domain/services/voice_session_coordinator.dart';
import 'package:life_os/features/voice_assistant/presentation/bloc/voice_assistant_bloc.dart';
import 'package:life_os/features/voice_assistant/presentation/bloc/voice_assistant_event.dart';

class _SyntheticSpeechEngineAdapter implements SpeechEngineAdapter {
  @override
  final VoiceEngineId engineId;

  @override
  final bool isStrictlyOffline;

  @override
  final bool supportsStreamingPartials;

  final FakeMonotonicClock clock;
  final StreamController<VoiceEnvelopeEvent> _events =
      StreamController<VoiceEnvelopeEvent>.broadcast(sync: true);

  bool available = true;
  bool supportsVietnamese = true;
  bool autoEmitReadyOnStart = true;
  EngineStartOutcome? startOutcomeOverride;

  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  String? lastStartedSessionId;
  int? lastStartedAttemptId;
  String? lastCancelledSessionId;
  int? lastCancelledAttemptId;
  int _seqCounter = 0;

  _SyntheticSpeechEngineAdapter({
    required this.engineId,
    required this.isStrictlyOffline,
    required this.clock,
    this.supportsStreamingPartials = true,
  });

  @override
  Stream<VoiceEnvelopeEvent> get events => _events.stream;

  @override
  Future<EngineAvailabilityCheck> checkAvailability({
    required String locale,
  }) async {
    return EngineAvailabilityCheck(
      engineId: engineId,
      isAvailable: available,
      supportsVietnamese: supportsVietnamese,
      serviceVersion: 'synthetic_v2',
      checkedAtEpochMs: clock.wallNow.millisecondsSinceEpoch,
    );
  }

  @override
  Future<EngineStartOutcome> startSession({
    required String sessionId,
    required int attemptId,
    required String ownerId,
    required String locale,
    required bool strictOffline,
  }) async {
    startCalls += 1;
    lastStartedSessionId = sessionId;
    lastStartedAttemptId = attemptId;
    if (startOutcomeOverride != null) {
      return startOutcomeOverride!;
    }
    if (autoEmitReadyOnStart) {
      emit(
        sessionId: sessionId,
        attemptId: attemptId,
        ownerId: ownerId,
        type: VoiceEnvelopeEventType.readyForSpeech,
      );
    }
    return EngineStartOutcome.success(
      awaitsExternalActivity: engineId == VoiceEngineId.systemDialog,
    );
  }

  @override
  Future<void> stopSession({
    required String sessionId,
    required int attemptId,
  }) async {
    stopCalls += 1;
  }

  @override
  Future<void> cancelSession({
    required String sessionId,
    required int attemptId,
  }) async {
    cancelCalls += 1;
    lastCancelledSessionId = sessionId;
    lastCancelledAttemptId = attemptId;
  }

  void emit({
    required String sessionId,
    required int attemptId,
    String ownerId = 'voice_sheet',
    required VoiceEnvelopeEventType type,
    int? sequenceNumber,
    String? text,
    double? rmsDb,
    bool isRealPcmEnergy = false,
    VoiceErrorKind? errorKind,
    String? errorCode,
    String? errorMessageVi,
    String? audioRoute,
  }) {
    _seqCounter += 1;
    _events.add(
      VoiceEnvelopeEvent(
        sessionId: sessionId,
        attemptId: attemptId,
        ownerId: ownerId,
        sequenceNumber: sequenceNumber ?? _seqCounter,
        engineId: engineId.wireValue,
        eventType: type,
        monotonicTimestampMs: clock.elapsedMilliseconds,
        text: text,
        rmsDb: rmsDb,
        isRealPcmEnergy: isRealPcmEnergy,
        errorKind: errorKind,
        errorCode: errorCode,
        errorMessageVi: errorMessageVi,
        audioRoute: audioRoute,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

class _FakeModelRepository implements LocalAsrModelRepository {
  bool hasInstalledAsr = false;
  List<LocalAsrModelInstallState> models = const <LocalAsrModelInstallState>[];

  @override
  Future<void> deleteModel(String modelId) async {}

  @override
  Future<LocalAsrModelInstallState> downloadModel(
    LocalAsrModelSpec spec, {
    void Function(LocalAsrDownloadProgress progress)? onProgress,
    bool enforceCommercialLicense = true,
  }) async {
    if (enforceCommercialLicense && !spec.commercialAllowed) {
      throw LocalAsrLicenseBlockedException(spec.id, spec.modelLicenseSpdx);
    }
    hasInstalledAsr = true;
    return LocalAsrModelInstallState(
      spec: spec,
      status: LocalAsrModelStatus.installed,
      installedVersion: spec.version,
    );
  }

  @override
  Future<LocalAsrModelInstallState> getModelState(String modelId) async {
    return LocalAsrModelInstallState(
      spec: LocalAsrModelCatalog.voskSmallVn,
      status: hasInstalledAsr
          ? LocalAsrModelStatus.installed
          : LocalAsrModelStatus.notDownloaded,
    );
  }

  @override
  Future<bool> hasVerifiedInstalledAsrModel() async => hasInstalledAsr;

  @override
  Future<List<LocalAsrModelInstallState>> listModels() async => models;

  @override
  Future<bool> rollbackModel(String modelId) async => false;

  @override
  Future<bool> verifyModelIntegrity(
    String modelId, {
    LocalAsrModelSpec? specOverride,
  }) async => hasInstalledAsr;
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('Voice Engine 2.0 Deterministic Suite', () {
    late FakeMonotonicClock clock;
    late FakeVoiceTimerFactory timerFactory;
    late InMemoryVoiceCapabilityStore capStore;
    late VoiceCapabilityRepositoryImpl capabilityRepo;
    late _FakeModelRepository modelRepo;
    late _SyntheticSpeechEngineAdapter googleEngine;
    late _SyntheticSpeechEngineAdapter onDeviceEngine;
    late _SyntheticSpeechEngineAdapter localAsrEngine;
    late _SyntheticSpeechEngineAdapter dialogEngine;
    late VoiceEnvironmentSnapshot env;

    VoiceSessionCoordinator buildCoordinator({
      EndpointPolicyConfig endpointConfig = const EndpointPolicyConfig(),
      VoiceRecognitionPreference preference =
          VoiceRecognitionPreference.hybridAuto,
      bool allowOnlineConsent = true,
      Future<bool> Function({
        required String sessionId,
        required int attemptId,
      })?
      permissionChecker,
      Future<void> Function({
        required String sessionId,
        required int attemptId,
      })?
      permissionRequester,
    }) {
      return VoiceSessionCoordinator(
        engineRegistry: SpeechEngineRegistry(<SpeechEngineAdapter>[
          googleEngine,
          onDeviceEngine,
          localAsrEngine,
          dialogEngine,
        ]),
        capabilityRepository: capabilityRepo,
        modelRepository: modelRepo,
        clock: clock,
        timerFactory: timerFactory,
        endpointConfig: endpointConfig,
        initialPreference: preference,
        initialAllowOnlineConsent: allowOnlineConsent,
        permissionChecker: permissionChecker,
        permissionRequester: permissionRequester,
        environmentProvider: () async => env.copyWithNow(clock.wallNow),
      );
    }

    setUp(() {
      clock = FakeMonotonicClock(initialElapsedMs: 1000);
      timerFactory = FakeVoiceTimerFactory(clock);
      capStore = InMemoryVoiceCapabilityStore();
      capabilityRepo = VoiceCapabilityRepositoryImpl(
        store: capStore,
        clock: clock,
      );
      modelRepo = _FakeModelRepository();
      googleEngine = _SyntheticSpeechEngineAdapter(
        engineId: VoiceEngineId.androidSpeech,
        isStrictlyOffline: false,
        clock: clock,
      );
      onDeviceEngine = _SyntheticSpeechEngineAdapter(
        engineId: VoiceEngineId.androidOnDevice,
        isStrictlyOffline: true,
        clock: clock,
      );
      localAsrEngine = _SyntheticSpeechEngineAdapter(
        engineId: VoiceEngineId.localAsr,
        isStrictlyOffline: true,
        clock: clock,
      );
      dialogEngine = _SyntheticSpeechEngineAdapter(
        engineId: VoiceEngineId.systemDialog,
        isStrictlyOffline: false,
        clock: clock,
        supportsStreamingPartials: false,
      );
      env = VoiceEnvironmentSnapshot(
        androidSdkInt: 35,
        osBuildFingerprint: 'samsung/a55/15',
        recognitionServiceVersion: 'com.google.android.tts@2026',
        locale: 'vi-VN',
        audioRoute: VoiceAudioRoute.builtInMic,
        isNetworkAvailable: true,
        isGoogleSpeechAvailable: true,
        isAndroidOnDeviceAvailable: true,
        isSystemDialogAvailable: true,
        nowEpochMs: clock.wallNow.millisecondsSinceEpoch,
      );
    });

    tearDown(() async {
      await googleEngine.dispose();
      await onDeviceEngine.dispose();
      await localAsrEngine.dispose();
      await dialogEngine.dispose();
    });

    test(
      '1. Strict FSM forbids listening -> review directly and enforces finalizing gate',
      () async {
        expect(
          VoiceSessionPhase.listening.canTransitionTo(VoiceSessionPhase.review),
          isFalse,
        );
        expect(
          VoiceSessionPhase.listening.canTransitionTo(
            VoiceSessionPhase.finalizing,
          ),
          isTrue,
        );
        expect(
          VoiceSessionPhase.finalizing.canTransitionTo(
            VoiceSessionPhase.review,
          ),
          isTrue,
        );
        expect(VoiceSessionPhase.finalizing.blocksNewStart, isTrue);
        expect(VoiceSessionPhase.finalizing.blocksConfirm, isTrue);

        final coordinator = buildCoordinator();
        addTearDown(coordinator.dispose);

        final start = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
        );
        expect(start.accepted, isTrue);
        expect(coordinator.currentSession.phase, VoiceSessionPhase.listening);

        clock.advance(const Duration(milliseconds: 250));
        googleEngine.emit(
          sessionId: start.sessionId!,
          attemptId: start.attemptId,
          type: VoiceEnvelopeEventType.partialResult,
          text: 'Ăn phở 50',
        );
        expect(
          coordinator.currentSnapshot.transcript.effectiveText,
          'Ăn phở 50',
        );

        // Stop moves STRICTLY to finalizing, NOT review!
        await coordinator.stopSession(sessionId: start.sessionId!);
        expect(coordinator.currentSession.phase, VoiceSessionPhase.finalizing);
        expect(
          coordinator.currentSession.terminalOutcome,
          VoiceTerminalOutcome.none,
        );

        // Confirm and rapid new start MUST be blocked while finalizing!
        expect(coordinator.beginSubmitting(), isFalse);
        final rapidDuringFinalizing = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
        );
        expect(rapidDuringFinalizing.accepted, isFalse);
        expect(rapidDuringFinalizing.rejectionReason, 'session_finalizing');

        // Partial mutation while finalizing is ignored!
        googleEngine.emit(
          sessionId: start.sessionId!,
          attemptId: start.attemptId,
          type: VoiceEnvelopeEventType.partialResult,
          text: 'SHOULD_NOT_OVERWRITE',
        );
        expect(
          coordinator.currentSnapshot.transcript.effectiveText,
          'Ăn phở 50',
        );

        // Final arrives -> finalizing -> review and replaces partial without duplication!
        clock.advance(const Duration(milliseconds: 180));
        googleEngine.emit(
          sessionId: start.sessionId!,
          attemptId: start.attemptId,
          type: VoiceEnvelopeEventType.finalResult,
          text: 'Ăn phở 55 nghìn',
        );

        expect(coordinator.currentSession.phase, VoiceSessionPhase.review);
        expect(
          coordinator.currentSession.terminalOutcome,
          VoiceTerminalOutcome.finalResult,
        );
        expect(
          coordinator.currentSnapshot.transcript.effectiveText,
          'Ăn phở 55 nghìn',
        );
      },
    );

    test(
      '2. Controlled finalizing timeout rescues non-empty partial and errors when empty',
      () async {
        final coordinator = buildCoordinator(
          endpointConfig: const EndpointPolicyConfig(
            finalizingTimeout: Duration(milliseconds: 2200),
          ),
        );
        addTearDown(coordinator.dispose);

        // Case A: non-empty partial rescued on finalizing timeout
        final s1 = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.dashboard,
        );
        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: s1.attemptId,
          type: VoiceEnvelopeEventType.partialResult,
          text: 'Cà phê 35 nghìn',
        );
        await coordinator.stopSession(sessionId: s1.sessionId!);
        expect(coordinator.currentSession.phase, VoiceSessionPhase.finalizing);

        timerFactory.advance(const Duration(milliseconds: 2199));
        expect(coordinator.currentSession.phase, VoiceSessionPhase.finalizing);

        timerFactory.advance(const Duration(milliseconds: 1));
        await _flushMicrotasks();
        expect(coordinator.currentSession.phase, VoiceSessionPhase.review);
        expect(
          coordinator.currentSession.terminalOutcome,
          VoiceTerminalOutcome.finalResult,
        );
        expect(
          coordinator.currentSnapshot.transcript.effectiveText,
          'Cà phê 35 nghìn',
        );
        expect(googleEngine.cancelCalls, 1);

        // Case B: empty transcript -> finalizingTimeout error
        await coordinator.resetToIdle();
        final s2 = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.dashboard,
        );
        await coordinator.stopSession(sessionId: s2.sessionId!);
        timerFactory.advance(const Duration(milliseconds: 2200));
        await _flushMicrotasks();

        expect(coordinator.currentSession.phase, VoiceSessionPhase.error);
        expect(
          coordinator.currentSession.lastErrorKind,
          VoiceErrorKind.finalizingTimeout,
        );
        expect(
          coordinator.currentSession.terminalOutcome,
          VoiceTerminalOutcome.error,
        );
      },
    );

    test(
      '3. Cancel produces single terminal outcome and ignores late final & error',
      () async {
        final coordinator = buildCoordinator();
        addTearDown(coordinator.dispose);

        final s1 = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
        );
        await coordinator.cancelSession(
          sessionId: s1.sessionId!,
          reason: 'sheet_closed',
        );

        expect(coordinator.currentSession.phase, VoiceSessionPhase.cancelled);
        expect(
          coordinator.currentSession.terminalOutcome,
          VoiceTerminalOutcome.cancelled,
        );
        expect(timerFactory.activeTimerCount, 0);

        // Late callbacks after cancel MUST be ignored
        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: s1.attemptId,
          type: VoiceEnvelopeEventType.finalResult,
          text: 'Late leaked text',
        );
        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: s1.attemptId,
          type: VoiceEnvelopeEventType.error,
          errorKind: VoiceErrorKind.clientError,
        );

        expect(coordinator.currentSession.phase, VoiceSessionPhase.cancelled);
        expect(
          coordinator.currentSession.terminalOutcome,
          VoiceTerminalOutcome.cancelled,
        );
        expect(coordinator.currentSnapshot.transcript.effectiveText, isEmpty);
      },
    );

    test(
      '4. Rapid repeated mic taps & Home Widget vs App contention enforce single mic owner',
      () async {
        final coordinator = buildCoordinator();
        addTearDown(coordinator.dispose);

        final f1 = coordinator.startSession(
          ownerId: 'home_widget',
          entryPoint: VoiceEntryPoint.homeWidget,
        );
        final f2 = coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.voiceSheet,
        );
        final results = await Future.wait(<Future<VoiceStartResult>>[f1, f2]);

        expect(results[0].accepted, isTrue);
        expect(results[1].accepted, isFalse);
        expect(coordinator.currentSession.ownerId, 'home_widget');
        expect(googleEngine.startCalls, 1);

        // Different sessionId cannot steal, stop, or cancel active owner
        expect(await coordinator.stopSession(sessionId: 'wrong_sid'), isFalse);
        expect(
          await coordinator.cancelSession(sessionId: 'wrong_sid'),
          isFalse,
        );
        expect(coordinator.currentSession.phase, VoiceSessionPhase.listening);
      },
    );

    test(
      '5. Permission granted AFTER cancel or while unfocused NEVER starts mic (VOICE-003)',
      () async {
        final coordinator = buildCoordinator(
          permissionChecker: ({required sessionId, required attemptId}) async =>
              false,
        );
        addTearDown(coordinator.dispose);

        // Case A: Cancel while awaiting permission, then late grant arrives
        final s1 = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.voiceSheet,
        );
        expect(
          coordinator.currentSession.phase,
          VoiceSessionPhase.requestingPermission,
        );
        expect(coordinator.currentSession.isAwaitingExternalActivity, isTrue);

        await coordinator.cancelSession(
          sessionId: s1.sessionId!,
          reason: 'user_closed_sheet',
        );

        final lateGrant = await coordinator.onPermissionResult(
          sessionId: s1.sessionId!,
          attemptId: s1.attemptId,
          granted: true,
          permanentlyDenied: false,
          isForegroundFocused: true,
        );
        expect(lateGrant.accepted, isFalse);
        expect(googleEngine.startCalls, 0);

        // Case B: Permission granted while app unfocused -> NEVER starts mic!
        final s2 = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.voiceSheet,
        );
        final unfocusedGrant = await coordinator.onPermissionResult(
          sessionId: s2.sessionId!,
          attemptId: s2.attemptId,
          granted: true,
          permanentlyDenied: false,
          isForegroundFocused: false,
        );
        expect(unfocusedGrant.accepted, isFalse);
        expect(
          unfocusedGrant.errorKind,
          VoiceErrorKind.interruptedByBackground,
        );
        expect(coordinator.currentSession.phase, VoiceSessionPhase.cancelled);
        expect(googleEngine.startCalls, 0);
      },
    );

    test(
      '6. Late final & error from stale attemptId are dropped cleanly',
      () async {
        final coordinator = buildCoordinator();
        addTearDown(coordinator.dispose);

        final s1 = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.financialAi,
        );
        expect(s1.attemptId, 1);

        final s2 = await coordinator.retrySession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.financialAi,
        );
        expect(s2.accepted, isTrue);
        expect(s2.attemptId, 2);

        // Emit stale final/error targeting attemptId=1 (or old session)
        googleEngine.emit(
          sessionId: s2.sessionId!,
          attemptId: 1,
          type: VoiceEnvelopeEventType.finalResult,
          text: 'Stale attempt 1 leak',
        );
        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: 1,
          type: VoiceEnvelopeEventType.error,
          errorKind: VoiceErrorKind.clientError,
        );

        expect(coordinator.currentSession.phase, VoiceSessionPhase.listening);
        expect(coordinator.currentSnapshot.transcript.effectiveText, isEmpty);
      },
    );

    test(
      '7. Missing RMS & missing partial callbacks NEVER switch engine or fail (VOICE-006)',
      () async {
        final coordinator = buildCoordinator();
        addTearDown(coordinator.dispose);

        final s1 = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
        );
        expect(coordinator.currentSession.phase, VoiceSessionPhase.listening);
        expect(coordinator.currentSnapshot.waveform.isRealAudioLevel, isFalse);
        expect(
          coordinator.currentSnapshot.waveform.isIndeterminateActive,
          isTrue,
        );

        // Advance 10 seconds with zero RMS and zero partial callbacks -> still listening on same engine!
        timerFactory.advance(const Duration(seconds: 10));
        expect(coordinator.currentSession.phase, VoiceSessionPhase.listening);
        expect(
          coordinator.currentSession.engineId,
          VoiceEngineId.androidSpeech,
        );
        expect(coordinator.currentSession.fallbackCount, 0);
        expect(dialogEngine.startCalls, 0);

        // Final eventually arrives -> succeeds cleanly
        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: s1.attemptId,
          type: VoiceEnvelopeEventType.finalResult,
          text: 'Đổ xăng 70 nghìn',
        );
        expect(coordinator.currentSession.phase, VoiceSessionPhase.review);
        expect(
          coordinator.currentSnapshot.transcript.effectiveText,
          'Đổ xăng 70 nghìn',
        );
      },
    );

    test(
      '8. App background/foreground preserves inline transcript, spares permission/system dialog, never auto-restarts',
      () async {
        // Case A: inline listening with partial -> background -> review, foreground does NOT auto-restart
        final coordinator = buildCoordinator();
        addTearDown(coordinator.dispose);

        final s1 = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
        );
        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: s1.attemptId,
          type: VoiceEnvelopeEventType.partialResult,
          text: 'Mua rau 25 nghìn',
        );

        await coordinator.onAppLifecycleChanged(true);
        expect(coordinator.currentSession.phase, VoiceSessionPhase.review);
        expect(
          coordinator.currentSnapshot.transcript.effectiveText,
          'Mua rau 25 nghìn',
        );
        expect(googleEngine.cancelCalls, 1);

        await coordinator.onAppLifecycleChanged(false);
        expect(googleEngine.startCalls, 1); // Never auto-restarts!

        // Case B: inline listening with empty text -> background -> cancelled
        await coordinator.resetToIdle();
        await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
        );
        await coordinator.onAppLifecycleChanged(true);
        expect(coordinator.currentSession.phase, VoiceSessionPhase.cancelled);

        // Case C: systemDialog active (isAwaitingExternalActivity == true) -> background does NOT cancel!
        await coordinator.resetToIdle();
        final sDialog = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
          preference: VoiceRecognitionPreference.systemDialog,
        );
        expect(sDialog.accepted, isTrue);
        expect(coordinator.currentSession.isAwaitingExternalActivity, isTrue);
        await coordinator.onAppLifecycleChanged(true);
        expect(coordinator.currentSession.phase, VoiceSessionPhase.listening);
        expect(dialogEngine.cancelCalls, 0);

        // Case D: requestingPermission -> background does NOT cancel!
        final permCoord = buildCoordinator(
          permissionChecker: ({required sessionId, required attemptId}) async =>
              false,
        );
        addTearDown(permCoord.dispose);
        await permCoord.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
        );
        await permCoord.onAppLifecycleChanged(true);
        expect(
          permCoord.currentSession.phase,
          VoiceSessionPhase.requestingPermission,
        );
      },
    );

    test(
      '9. Offline Strict NEVER falls back to online under network loss or airplane mode (VOICE-007)',
      () async {
        // Offline environment, no local model, no android on-device
        env = VoiceEnvironmentSnapshot(
          androidSdkInt: 30,
          osBuildFingerprint: 'xiaomi/alioth/11',
          recognitionServiceVersion: 'com.google.android.tts@2026',
          isNetworkAvailable: false,
          isGoogleSpeechAvailable: true,
          isAndroidOnDeviceAvailable: false,
          isSystemDialogAvailable: true,
          nowEpochMs: clock.wallNow.millisecondsSinceEpoch,
        );

        final coordinator = buildCoordinator(
          preference: VoiceRecognitionPreference.offlineStrict,
        );
        addTearDown(coordinator.dispose);

        final blocked = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
          preference: VoiceRecognitionPreference.offlineStrict,
        );
        expect(blocked.accepted, isFalse);
        expect(blocked.errorKind, VoiceErrorKind.offlineModelMissing);
        expect(coordinator.currentSession.phase, VoiceSessionPhase.error);
        expect(googleEngine.startCalls, 0);
        expect(dialogEngine.startCalls, 0);

        // Even when online Google & dialog are available, offlineStrict with localAsr installed ONLY picks localAsr!
        env = VoiceEnvironmentSnapshot(
          androidSdkInt: 30,
          osBuildFingerprint: 'xiaomi/alioth/11',
          recognitionServiceVersion: 'com.google.android.tts@2026',
          isNetworkAvailable: true,
          isGoogleSpeechAvailable: true,
          isAndroidOnDeviceAvailable: false,
          isSystemDialogAvailable: true,
          nowEpochMs: clock.wallNow.millisecondsSinceEpoch,
        );
        modelRepo.hasInstalledAsr = true;
        await coordinator.resetToIdle();

        final offlineOk = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
          preference: VoiceRecognitionPreference.offlineStrict,
        );
        expect(offlineOk.accepted, isTrue);
        expect(coordinator.currentSession.engineId, VoiceEngineId.localAsr);
        expect(googleEngine.startCalls, 0);
        expect(dialogEngine.startCalls, 0);

        // If localAsr fails in offlineStrict, NEVER falls back to online!
        localAsrEngine.emit(
          sessionId: offlineOk.sessionId!,
          attemptId: offlineOk.attemptId,
          type: VoiceEnvelopeEventType.error,
          errorKind: VoiceErrorKind.audioError,
        );
        await _flushMicrotasks();
        expect(coordinator.currentSession.phase, VoiceSessionPhase.error);
        expect(googleEngine.startCalls, 0);
        expect(dialogEngine.startCalls, 0);
      },
    );

    test(
      '10. Bluetooth audio route change & incoming call audioFocusLost',
      () async {
        final coordinator = buildCoordinator();
        addTearDown(coordinator.dispose);

        final s1 = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.dashboard,
        );

        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: s1.attemptId,
          type: VoiceEnvelopeEventType.audioRouteChanged,
          audioRoute: 'bluetooth_sco',
        );
        expect(
          coordinator.currentSession.audioRoute,
          VoiceAudioRoute.bluetoothSco,
        );
        expect(coordinator.currentSession.phase, VoiceSessionPhase.listening);

        // Incoming call steals audio focus
        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: s1.attemptId,
          type: VoiceEnvelopeEventType.audioFocusLost,
        );
        await _flushMicrotasks();

        expect(coordinator.currentSession.phase, VoiceSessionPhase.error);
        expect(
          coordinator.currentSession.lastErrorKind,
          VoiceErrorKind.audioFocusLost,
        );
        expect(
          coordinator.currentSession.terminalOutcome,
          VoiceTerminalOutcome.error,
        );
      },
    );

    test(
      '11. Account switch / sign-out cancels active capture and wipes transcript & timeline',
      () async {
        final coordinator = buildCoordinator();
        addTearDown(coordinator.dispose);

        final s1 = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.financePage,
        );
        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: s1.attemptId,
          type: VoiceEnvelopeEventType.partialResult,
          text: 'Chuyển khoản 5 triệu',
        );
        expect(
          coordinator.currentSnapshot.transcript.effectiveText,
          'Chuyển khoản 5 triệu',
        );

        await coordinator.onUserAccountChangedOrSignedOut();
        expect(coordinator.currentSession.phase, VoiceSessionPhase.idle);
        expect(coordinator.currentSession.sessionId, isEmpty);
        expect(coordinator.currentSnapshot.transcript.effectiveText, isEmpty);
        expect(coordinator.currentSnapshot.diagnostics.recentTimeline, isEmpty);
        expect(googleEngine.cancelCalls, 1);
      },
    );

    test(
      '12. Bounded retry: recognizerBusy retries max once; non-retryable retries 0 times',
      () async {
        // Disable fallbacks to verify strict retry count on single engine
        final singleEnv = VoiceEnvironmentSnapshot(
          androidSdkInt: 30,
          osBuildFingerprint: 'pixel/6/11',
          recognitionServiceVersion: 'tts@1',
          isNetworkAvailable: true,
          isGoogleSpeechAvailable: true,
          isAndroidOnDeviceAvailable: false,
          isSystemDialogAvailable: false,
          nowEpochMs: clock.wallNow.millisecondsSinceEpoch,
        );
        env = singleEnv;
        googleEngine.autoEmitReadyOnStart = false;

        final coordinator = buildCoordinator(
          preference: VoiceRecognitionPreference.onlineGoogle,
        );
        addTearDown(coordinator.dispose);

        final s1 = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
        );
        expect(googleEngine.startCalls, 1);

        // 1st recognizerBusy -> schedules 1 transient retry
        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: 1,
          type: VoiceEnvelopeEventType.error,
          errorKind: VoiceErrorKind.recognizerBusy,
        );
        await _flushMicrotasks();
        expect(coordinator.currentSession.retryCount, 1);
        expect(coordinator.currentSession.attemptId, 2);

        timerFactory.advance(const Duration(milliseconds: 250));
        await _flushMicrotasks();
        expect(googleEngine.startCalls, 2);

        // 2nd recognizerBusy -> MUST NOT retry infinitely!
        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: 2,
          type: VoiceEnvelopeEventType.error,
          errorKind: VoiceErrorKind.recognizerBusy,
        );
        await _flushMicrotasks();
        expect(coordinator.currentSession.phase, VoiceSessionPhase.error);
        expect(coordinator.currentSession.retryCount, 1);
        expect(googleEngine.startCalls, 2);

        // Non-retryable microphoneInUse retries 0 times
        await coordinator.resetToIdle();
        final s2 = await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
        );
        googleEngine.emit(
          sessionId: s2.sessionId!,
          attemptId: s2.attemptId,
          type: VoiceEnvelopeEventType.error,
          errorKind: VoiceErrorKind.microphoneInUse,
        );
        await _flushMicrotasks();
        expect(coordinator.currentSession.phase, VoiceSessionPhase.error);
        expect(coordinator.currentSession.retryCount, 0);
        expect(
          coordinator.currentSession.lastErrorKind,
          VoiceErrorKind.microphoneInUse,
        );
      },
    );

    test(
      '13. Capability cache TTL expiration, environment invalidation, failure demotion, and reset',
      () async {
        const policy = EngineSelectionPolicy();
        final baseTime = clock.wallNow.millisecondsSinceEpoch;

        // 2 consecutive failures demote androidSpeech behind androidOnDevice & systemDialog
        await capabilityRepo.recordError(
          engineId: VoiceEngineId.androidSpeech,
          environment: env,
          errorCode: 'CLIENT_ERROR',
        );
        await capabilityRepo.recordError(
          engineId: VoiceEngineId.androidSpeech,
          environment: env,
          errorCode: 'CLIENT_ERROR',
        );

        final caps = await capabilityRepo.loadEntries();
        expect(caps.single.consecutiveErrorCount, 2);
        expect(caps.single.reliabilityScore, lessThan(0.4));

        final demotedRes = policy.selectEngines(
          preference: VoiceRecognitionPreference.hybridAuto,
          environment: env,
          capabilityEntries: caps,
          allowOnlineConsent: true,
          localModelInstalled: false,
        );
        expect(demotedRes.orderedEngines.first, VoiceEngineId.androidOnDevice);
        expect(demotedRes.orderedEngines.last, VoiceEngineId.androidSpeech);

        // Environment change (e.g. Bluetooth SCO route) does NOT apply builtInMic failures!
        final btEnv = VoiceEnvironmentSnapshot(
          androidSdkInt: env.androidSdkInt,
          osBuildFingerprint: env.osBuildFingerprint,
          recognitionServiceVersion: env.recognitionServiceVersion,
          audioRoute: VoiceAudioRoute.bluetoothSco,
          nowEpochMs: baseTime,
        );
        final btRes = policy.selectEngines(
          preference: VoiceRecognitionPreference.hybridAuto,
          environment: btEnv,
          capabilityEntries: caps,
          allowOnlineConsent: true,
          localModelInstalled: false,
        );
        expect(btRes.orderedEngines.first, VoiceEngineId.androidSpeech);

        // TTL expiration (> 24h) automatically clears demotion without permanent ban!
        final expiredEnv = VoiceEnvironmentSnapshot(
          androidSdkInt: env.androidSdkInt,
          osBuildFingerprint: env.osBuildFingerprint,
          recognitionServiceVersion: env.recognitionServiceVersion,
          audioRoute: env.audioRoute,
          nowEpochMs: baseTime + VoiceEngineCapabilityEntry.defaultTtlMs + 1000,
        );
        final afterTtlRes = policy.selectEngines(
          preference: VoiceRecognitionPreference.hybridAuto,
          environment: expiredEnv,
          capabilityEntries: caps,
          allowOnlineConsent: true,
          localModelInstalled: false,
        );
        expect(afterTtlRes.orderedEngines.first, VoiceEngineId.androidSpeech);

        // Explicit reset clears stored entries
        final coordinator = buildCoordinator();
        addTearDown(coordinator.dispose);
        await coordinator.resetCapabilities();
        expect(await capabilityRepo.loadEntries(), isEmpty);
      },
    );

    test(
      '14. Wall-clock jumps do NOT break monotonic preparing or finalizing timeouts',
      () async {
        googleEngine.autoEmitReadyOnStart = false;
        final coordinator = buildCoordinator(
          endpointConfig: const EndpointPolicyConfig(
            preparingTimeout: Duration(milliseconds: 4000),
          ),
        );
        addTearDown(coordinator.dispose);

        await coordinator.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.quickCreate,
        );
        expect(coordinator.currentSession.phase, VoiceSessionPhase.preparing);

        // Jump wall clock forward by 10 hours (e.g., NTP sync / timezone switch)
        clock.jumpWallClock(const Duration(hours: 10));
        expect(coordinator.currentSession.phase, VoiceSessionPhase.preparing);

        // Only advancing monotonic timer triggers preparing timeout
        timerFactory.advance(const Duration(milliseconds: 3999));
        expect(coordinator.currentSession.phase, VoiceSessionPhase.preparing);
        timerFactory.advance(const Duration(milliseconds: 1));
        await _flushMicrotasks();
        expect(
          coordinator.currentSession.fallbackCount,
          greaterThanOrEqualTo(1),
        );
      },
    );

    test(
      '15. Real AdaptiveEnergyZcrVad & Pcm16RingBuffer distinguish speech vs noise with bounded pre-roll',
      () {
        final ring = Pcm16RingBuffer(
          sampleRateHz: 16000,
          preRollMs: 300,
          capacitySamples: 16000, // 1s bounded
        );
        final vad = AdaptiveEnergyZcrVad(ringBuffer: ring);

        // Write more than capacity to verify bounded ring buffer does not grow unboundedly
        final quietFrame = List<int>.generate(
          320,
          (i) => (i.isEven ? 12 : -12),
        );
        for (var t = 0; t < 60; t++) {
          final res = vad.processPcm16Frame(
            quietFrame,
            sampleRateHz: 16000,
            monotonicTimestampMs: t * 20,
          );
          expect(res.isSpeech, isFalse);
        }
        expect(ring.length, 16000);
        expect(ring.readPreRoll().length, 4800);

        // Feed voiced 400 Hz sine speech frame (~16000 amplitude) -> detects speech + pre-roll
        final voicedFrame = List<int>.generate(320, (i) {
          final angle = 2 * math.pi * 400 * i / 16000;
          return (math.sin(angle) * 14000).round();
        });
        final speechRes = vad.processPcm16Frame(
          voicedFrame,
          sampleRateHz: 16000,
          monotonicTimestampMs: 1220,
        );
        expect(speechRes.isSpeech, isTrue);
        expect(speechRes.isPreRollTriggered, isTrue);
        expect(speechRes.probability, greaterThan(0.6));
        expect(speechRes.energyDbfs, greaterThan(-20.0));

        // Immediate quiet frame within 240ms hangover stays active, then drops to silence
        final hangoverRes = vad.processPcm16Frame(
          quietFrame,
          sampleRateHz: 16000,
          monotonicTimestampMs: 1300,
        );
        expect(hangoverRes.isSpeech, isTrue);
        expect(hangoverRes.isHangoverActive, isTrue);

        final silentAfterHangover = vad.processPcm16Frame(
          quietFrame,
          sampleRateHz: 16000,
          monotonicTimestampMs: 1600,
        );
        expect(silentAfterHangover.isSpeech, isFalse);
        expect(silentAfterHangover.isHangoverActive, isFalse);
      },
    );

    test(
      '16. Sanitized VoiceDiagnosticsReport never leaks transcript, amounts, accounts, or PII',
      () async {
        final coordinator = buildCoordinator();
        addTearDown(coordinator.dispose);

        final s1 = await coordinator.startSession(
          ownerId: 'uid_secret_123456',
          entryPoint: VoiceEntryPoint.financialAi,
        );
        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: s1.attemptId,
          type: VoiceEnvelopeEventType.partialResult,
          text: 'Chuyển 9850000 cho tài khoản 1903456789012',
        );
        googleEngine.emit(
          sessionId: s1.sessionId!,
          attemptId: s1.attemptId,
          type: VoiceEnvelopeEventType.finalResult,
          text: 'Chuyển 9850000 cho tài khoản 1903456789012',
        );

        final report = coordinator.currentSnapshot.diagnostics;
        final jsonStr = report.toSanitizedJson();
        final textStr = report.toSanitizedTextReport();

        for (final sensitive in <String>[
          'Chuyển',
          '9850000',
          '1903456789012',
          'uid_secret_123456',
        ]) {
          expect(jsonStr.contains(sensitive), isFalse);
          expect(textStr.contains(sensitive), isFalse);
        }

        final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
        expect(parsed['schemaVersion'], 'voice_diag_v2');
        expect(
          (parsed['session'] as Map<String, dynamic>)['currentPhase'],
          'review',
        );
      },
    );

    test(
      '17. VoiceNativeChannelDataSource parses legacy v1 maps and v2 envelopes cleanly',
      () async {
        final ds = VoiceNativeChannelDataSource(clock: clock);
        addTearDown(ds.dispose);

        final captured = <VoiceEnvelopeEvent>[];
        final sub = ds.events.listen(captured.add);
        addTearDown(sub.cancel);

        ds.handleRawNativeMap(<String, dynamic>{
          'type': 'state',
          'status': 'listening',
          'sessionToken': 'legacy_tok_1',
        });
        ds.handleRawNativeMap(<String, dynamic>{
          'type': 'partial',
          'text': 'Ăn sáng 30k',
          'sessionToken': 'legacy_tok_1',
        });
        ds.handleRawNativeMap(<String, dynamic>{
          'type': 'final',
          'text': 'Ăn sáng 35 nghìn',
          'sessionToken': 'legacy_tok_1',
        });
        ds.handleRawNativeMap(<String, dynamic>{
          'eventType': 'pcmEnergy',
          'sessionId': 'v2_tok_2',
          'attemptId': 3,
          'sequenceNumber': 9,
          'engineId': 'local_asr',
          'rmsDb': -22.5,
          'isRealPcmEnergy': true,
        });

        await _flushMicrotasks();
        expect(captured.length, 4);
        expect(captured[0].eventType, VoiceEnvelopeEventType.readyForSpeech);
        expect(captured[0].sessionId, 'legacy_tok_1');
        expect(captured[1].eventType, VoiceEnvelopeEventType.partialResult);
        expect(captured[2].eventType, VoiceEnvelopeEventType.finalResult);
        expect(captured[3].eventType, VoiceEnvelopeEventType.pcmEnergy);
        expect(captured[3].isRealPcmEnergy, isTrue);
        expect(captured[3].attemptId, 3);
        expect(captured[3].sequenceNumber, 9);
      },
    );

    test(
      '18. VoiceAssistantBloc end-to-end events, edits, submit, and model license block',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'lifeos_bloc_asr_',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final realModelManager = LocalAsrModelManager(
          rootDirectory: tempDir,
          httpClient: MockClient((_) async => http.Response('err', 500)),
        );

        final coordinator = buildCoordinator();
        final bloc = VoiceAssistantBloc(
          coordinator: coordinator,
          modelRepository: realModelManager,
          disposeCoordinatorOnClose: true,
        );
        addTearDown(bloc.close);

        final initializedFuture = bloc.stream.firstWhere(
          (s) => s.models.length == LocalAsrModelCatalog.defaults.length,
        );
        bloc.add(const VoiceAssistantInitialized());
        final initializedState = await initializedFuture;
        expect(
          initializedState.models.length,
          LocalAsrModelCatalog.defaults.length,
        );

        bloc.add(
          const VoiceStartRequested(
            ownerId: 'voice_sheet',
            entryPoint: VoiceEntryPoint.quickCreate,
          ),
        );
        await _flushMicrotasks();
        expect(bloc.state.isListening, isTrue);

        final sid = bloc.state.session.sessionId;
        final aid = bloc.state.session.attemptId;
        googleEngine.emit(
          sessionId: sid,
          attemptId: aid,
          type: VoiceEnvelopeEventType.partialResult,
          text: 'Cà phê 30',
        );
        await _flushMicrotasks();
        expect(bloc.state.effectiveText, 'Cà phê 30');

        bloc.add(VoiceStopRequested(sessionId: sid));
        await _flushMicrotasks();
        expect(bloc.state.isFinalizing, isTrue);

        googleEngine.emit(
          sessionId: sid,
          attemptId: aid,
          type: VoiceEnvelopeEventType.finalResult,
          text: 'Cà phê 35 nghìn',
        );
        await _flushMicrotasks();
        expect(bloc.state.isReview, isTrue);
        expect(bloc.state.effectiveText, 'Cà phê 35 nghìn');

        bloc.add(const VoiceTranscriptEdited('Cà phê sữa 40 nghìn'));
        await _flushMicrotasks();
        expect(bloc.state.effectiveText, 'Cà phê sữa 40 nghìn');

        bloc.add(const VoiceSubmitStarted());
        await _flushMicrotasks();
        expect(bloc.state.isSubmitting, isTrue);

        bloc.add(const VoiceSubmitCompleted());
        await _flushMicrotasks();
        expect(bloc.state.phase, VoiceSessionPhase.completed);

        // Attempting to download non-commercial NC-ND model triggers safe toast error
        final licenseBlockedFuture = bloc.stream.firstWhere(
          (s) => s.isToastError && s.toastMessageVi != null,
        );
        bloc.add(
          const VoiceModelDownloadRequested(
            LocalAsrModelCatalog.sherpaZipformerViNc,
          ),
        );
        final blockedState = await licenseBlockedFuture;
        expect(blockedState.isToastError, isTrue);
        expect(blockedState.toastMessageVi, isNotNull);
      },
    );

    test(
      '19. Google Speech disabled fails cleanly and smartAutoEndpoint extends silence on dangling clauses',
      () async {
        env = VoiceEnvironmentSnapshot(
          androidSdkInt: 30,
          osBuildFingerprint: 'oem/no_google/11',
          recognitionServiceVersion: 'none',
          isNetworkAvailable: true,
          isGoogleSpeechAvailable: false,
          isAndroidOnDeviceAvailable: false,
          isSystemDialogAvailable: false,
          nowEpochMs: clock.wallNow.millisecondsSinceEpoch,
        );
        final blockedCoord = buildCoordinator();
        addTearDown(blockedCoord.dispose);

        final noEngineRes = await blockedCoord.startSession(
          ownerId: 'voice_sheet',
          entryPoint: VoiceEntryPoint.menuDirectory,
        );
        expect(noEngineRes.accepted, isFalse);
        expect(noEngineRes.errorKind, VoiceErrorKind.noEngineAvailable);

        // EndpointPolicyEvaluator: explicitStopOnly vs smartAutoEndpoint
        const evaluator = EndpointPolicyEvaluator();
        const explicitConfig = EndpointPolicyConfig(
          mode: VoiceEndpointMode.explicitStopOnly,
        );
        expect(
          evaluator
              .evaluate(
                config: explicitConfig,
                acoustic: const AcousticEndpointSignal(
                  hasSpeechStarted: true,
                  speechDurationMs: 1200,
                  silenceDurationMs: 10000,
                  utteranceElapsedMs: 12000,
                  hasActiveRmsOrVad: true,
                ),
                semanticHint: const SemanticCompletenessHint(
                  hasTranscript: true,
                  hasActionableIntent: true,
                  hasDanglingConnector: false,
                  endsWithBareNumber: false,
                ),
              )
              .kind,
          EndpointDecisionKind.continueListening,
        );
        expect(
          evaluator
              .evaluate(
                config: explicitConfig,
                acoustic: const AcousticEndpointSignal(
                  hasSpeechStarted: true,
                  speechDurationMs: 40000,
                  silenceDurationMs: 0,
                  utteranceElapsedMs: 45000,
                  hasActiveRmsOrVad: true,
                ),
              )
              .kind,
          EndpointDecisionKind.triggerGracefulStop,
        );

        const smartConfig = EndpointPolicyConfig(
          mode: VoiceEndpointMode.smartAutoEndpoint,
        );
        // Dangling connector ("và") waits 3200ms rather than 2000ms
        expect(
          evaluator
              .evaluate(
                config: smartConfig,
                acoustic: const AcousticEndpointSignal(
                  hasSpeechStarted: true,
                  speechDurationMs: 1200,
                  silenceDurationMs: 2200,
                  utteranceElapsedMs: 3400,
                  hasActiveRmsOrVad: true,
                ),
                semanticHint: const SemanticCompletenessHint(
                  hasTranscript: true,
                  hasActionableIntent: false,
                  hasDanglingConnector: true,
                  endsWithBareNumber: false,
                ),
              )
              .kind,
          EndpointDecisionKind.continueListening,
        );
        expect(
          evaluator
              .evaluate(
                config: smartConfig,
                acoustic: const AcousticEndpointSignal(
                  hasSpeechStarted: true,
                  speechDurationMs: 1200,
                  silenceDurationMs: 3200,
                  utteranceElapsedMs: 4400,
                  hasActiveRmsOrVad: true,
                ),
                semanticHint: const SemanticCompletenessHint(
                  hasTranscript: true,
                  hasActionableIntent: false,
                  hasDanglingConnector: true,
                  endsWithBareNumber: false,
                ),
              )
              .kind,
          EndpointDecisionKind.triggerGracefulStop,
        );
      },
    );

    test(
      '20. SpeechEngineAdapters enforce offline & model prerequisites',
      () async {
        final ds = VoiceNativeChannelDataSource(clock: clock);
        addTearDown(ds.dispose);

        final androidSpeech = AndroidSpeechEngine(ds);
        final speechOfflineAttempt = await androidSpeech.startSession(
          sessionId: 's_eng',
          attemptId: 1,
          ownerId: 'voice_sheet',
          locale: 'vi-VN',
          strictOffline: true,
        );
        expect(speechOfflineAttempt.started, isFalse);
        expect(
          speechOfflineAttempt.errorKind,
          VoiceErrorKind.noEngineAvailable,
        );

        final sysDialog = SystemDialogEngine(ds);
        final dialogOfflineAttempt = await sysDialog.startSession(
          sessionId: 's_eng',
          attemptId: 1,
          ownerId: 'voice_sheet',
          locale: 'vi-VN',
          strictOffline: true,
        );
        expect(dialogOfflineAttempt.started, isFalse);

        final localAsr = LocalAsrEngine(
          modelRepository: modelRepo,
          dataSource: ds,
        );
        modelRepo.hasInstalledAsr = false;
        final missingModelStart = await localAsr.startSession(
          sessionId: 's_eng',
          attemptId: 1,
          ownerId: 'voice_sheet',
          locale: 'vi-VN',
          strictOffline: true,
        );
        expect(missingModelStart.started, isFalse);
        expect(missingModelStart.errorKind, VoiceErrorKind.offlineModelMissing);
      },
    );
  });
}

extension _EnvCopy on VoiceEnvironmentSnapshot {
  VoiceEnvironmentSnapshot copyWithNow(DateTime wallNow) {
    return VoiceEnvironmentSnapshot(
      androidSdkInt: androidSdkInt,
      osBuildFingerprint: osBuildFingerprint,
      recognitionServiceVersion: recognitionServiceVersion,
      locale: locale,
      audioRoute: audioRoute,
      isNetworkAvailable: isNetworkAvailable,
      isGoogleSpeechAvailable: isGoogleSpeechAvailable,
      isAndroidOnDeviceAvailable: isAndroidOnDeviceAvailable,
      isSystemDialogAvailable: isSystemDialogAvailable,
      nowEpochMs: wallNow.millisecondsSinceEpoch,
    );
  }
}
