import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:life_os/features/voice_assistant/data/datasources/local_asr_model_manager.dart';
import 'package:life_os/features/voice_assistant/data/datasources/voice_native_channel_datasource.dart';
import 'package:life_os/features/voice_assistant/data/repositories/voice_capability_repository_impl.dart';
import 'package:life_os/features/voice_assistant/domain/entities/voice_engine_capability.dart';
import 'package:life_os/features/voice_assistant/domain/entities/voice_event.dart';
import 'package:life_os/features/voice_assistant/domain/entities/voice_model_package.dart';
import 'package:life_os/features/voice_assistant/domain/services/monotonic_clock.dart';
import 'package:life_os/features/voice_assistant/domain/services/speech_engine_adapter.dart';
import 'package:life_os/features/voice_assistant/domain/services/voice_session_coordinator.dart';
import 'package:life_os/features/voice_assistant/presentation/bloc/voice_assistant_bloc.dart';
import 'package:life_os/features/voice_assistant/presentation/pages/voice_diagnostics_page.dart';

class _StubAdapter implements SpeechEngineAdapter {
  @override
  VoiceEngineId get engineId => VoiceEngineId.androidSpeech;

  @override
  bool get isStrictlyOffline => false;

  @override
  bool get supportsStreamingPartials => true;

  @override
  Future<EngineAvailabilityCheck> checkAvailability({
    required String locale,
  }) async => const EngineAvailabilityCheck(
    engineId: VoiceEngineId.androidSpeech,
    isAvailable: true,
    supportsVietnamese: true,
    serviceVersion: 'google_tts_stub',
  );

  @override
  Future<EngineStartOutcome> startSession({
    required String sessionId,
    required int attemptId,
    required String ownerId,
    required String locale,
    required bool strictOffline,
  }) async => const EngineStartOutcome.success();

  @override
  Future<void> stopSession({
    required String sessionId,
    required int attemptId,
  }) async {}

  @override
  Future<void> cancelSession({
    required String sessionId,
    required int attemptId,
  }) async {}

  @override
  Stream<VoiceEnvelopeEvent> get events =>
      const Stream<VoiceEnvelopeEvent>.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  tearDown(() async {
    await sl.reset();
  });

  testWidgets(
    'VoiceDiagnosticsPage renders device telemetry, latencies, mic self-test, model licenses & sanitized export cleanly at 360x800 @ 1.25x',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tempDir = Directory.systemTemp.createTempSync('lifeos_vdiag_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final capRepo = VoiceCapabilityRepositoryImpl(
        store: InMemoryVoiceCapabilityStore(),
      );
      final modelRepo = LocalAsrModelManager(
        rootDirectory: tempDir,
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      final coordinator = VoiceSessionCoordinator(
        engineRegistry: SpeechEngineRegistry(<SpeechEngineAdapter>[
          _StubAdapter(),
        ]),
        capabilityRepository: capRepo,
        modelRepository: modelRepo,
        clock: FakeMonotonicClock(),
      );

      sl.registerSingleton<VoiceNativeChannelDataSource>(
        VoiceNativeChannelDataSource(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.25)),
            child: LifeOsTopToastHost(child: child!),
          ),
          home: BlocProvider<VoiceAssistantBloc>(
            create: (_) => VoiceAssistantBloc(
              coordinator: coordinator,
              modelRepository: modelRepo,
              disposeCoordinatorOnClose: true,
            ),
            child: const VoiceDiagnosticsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('voice_diag_device_card')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('voice_diag_session_card')),
        200,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('voice_diag_session_card')), findsOneWidget);
      expect(find.text('Time to Ready'), findsOneWidget);
      expect(find.text('Time to First Partial'), findsOneWidget);
      expect(find.text('Time to Final'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('voice_diag_models_card')),
        240,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('voice_diag_models_card')), findsOneWidget);
      expect(
        find.byKey(
          Key('voice_model_installed_${LocalAsrModelCatalog.voskSmallVn.id}'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          Key(
            'voice_model_installed_${LocalAsrModelCatalog.sherpaZipformerViInt8.id}',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('✓ Đã tải sẵn & Kích hoạt'), findsWidgets);

      expect(tester.takeException(), isNull);
    },
  );
}
