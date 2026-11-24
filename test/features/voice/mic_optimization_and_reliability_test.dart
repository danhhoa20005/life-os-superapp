import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/services/native_voice_assistant_bridge.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';

class _NoOpCalendarDriver implements DeviceCalendarDriver {
  const _NoOpCalendarDriver();

  @override
  bool get isSupportedPlatform => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<List<DeviceCalendarInfo>> listCalendars() async => const [];

  @override
  Future<List<DeviceCalendarEventItem>> listEvents({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async => const [];

  @override
  Future<int?> upsertEvent({
    int? deviceEventId,
    int? deviceCalendarId,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool isAllDay = false,
    String timeZone = 'Asia/Ho_Chi_Minh',
    String? rrule,
    int reminderMinutesBefore = 15,
  }) async => null;

  @override
  Future<bool> deleteEvent(int deviceEventId) async => false;
}

class _AdvancedMockVoiceDriver implements AdvancedVoiceAssistantDriver {
  final StreamController<VoiceAssistantSignal> controller =
      StreamController<VoiceAssistantSignal>.broadcast();
  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;
  String lastEngineMode = 'auto';
  bool lastPreferSystemDialog = false;
  bool emitInitializingFirst = true;

  @override
  bool get isSupportedPlatform => true;

  @override
  Future<String> startListening() => startListeningSession();

  @override
  Future<String> startListeningSession({
    String? sessionToken,
    bool preferSystemDialog = false,
    String engineMode = 'auto',
  }) async {
    startCount++;
    lastPreferSystemDialog = preferSystemDialog;
    lastEngineMode = engineMode;
    if (emitInitializingFirst) {
      controller.add(const VoiceStateSignal('initializing'));
    } else {
      controller.add(const VoiceStateSignal('listening'));
    }
    return 'LISTENING_STARTED';
  }

  @override
  Future<void> stopListening() async {
    stopCount++;
  }

  @override
  Future<void> cancelListeningSession({String? sessionToken}) async {
    cancelCount++;
  }

  @override
  Future<bool> openMicrophoneSettings() async => true;

  @override
  Future<VoiceDiagnosticsSnapshot> getDiagnostics() async {
    return const VoiceDiagnosticsSnapshot(
      hardwareMicAvailable: true,
      hasRecordPermission: true,
      isRecognitionAvailable: true,
      isOnDeviceAvailable: true,
      hasSystemSpeechDialog: true,
      availableEngines: <String>[
        'service:com.google.android.tts',
        'service:com.google.android.googlequicksearchbox',
      ],
      activeEngineLabel: 'service:com.google.android.tts',
      sdkInt: 35,
      manufacturer: 'Samsung',
    );
  }

  @override
  Stream<VoiceAssistantSignal> watchSignals() => controller.stream;

  Future<void> dispose() async {
    await controller.close();
  }
}

void main() {
  setUp(() async {
    await UserBehaviorPrefs.resetForTest();
    NativeDeviceCalendarBridge.setDriverOverride(const _NoOpCalendarDriver());
  });

  tearDown(() async {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    NativeVoiceAssistantBridge.setDriverOverride(null);
    await sl.reset();
  });

  group('1. Bridge Multi-Segment Combiner & Diagnostics Contract', () {
    test(
      'combinePrefixAndSegment preserves prior clauses without duplicating cumulative transcripts',
      () {
        expect(
          NativeVoiceAssistantBridge.combinePrefixAndSegment(
            '',
            'Ăn phở 55 nghìn',
          ),
          'Ăn phở 55 nghìn',
        );
        expect(
          NativeVoiceAssistantBridge.combinePrefixAndSegment(
            'Ăn phở 55 nghìn',
            'Cà phê 35 nghìn',
          ),
          'Ăn phở 55 nghìn, Cà phê 35 nghìn',
        );
        expect(
          NativeVoiceAssistantBridge.combinePrefixAndSegment(
            'Ăn phở 55 nghìn, ',
            'Đổ xăng 70 nghìn',
          ),
          'Ăn phở 55 nghìn, Đổ xăng 70 nghìn',
        );
        // Cumulative engine re-emission must not duplicate prefix
        expect(
          NativeVoiceAssistantBridge.combinePrefixAndSegment(
            'Ăn phở 55 nghìn',
            'Ăn phở 55 nghìn với bạn',
          ),
          'Ăn phở 55 nghìn với bạn',
        );
      },
    );

    test(
      'VoiceDiagnosticsSnapshot maps OEM & Android 13+ engine labels accurately',
      () {
        final sysSnap = VoiceDiagnosticsSnapshot.fromMap(<String, dynamic>{
          'hardwareMicAvailable': true,
          'hasRecordPermission': true,
          'isRecognitionAvailable': true,
          'isOnDeviceAvailable': true,
          'hasSystemSpeechDialog': true,
          'availableEngines': <String>['system_default'],
          'activeEngineLabel': 'system_default',
          'sdkInt': 34,
          'manufacturer': 'Xiaomi',
        });
        expect(sysSnap.readableEngineSummaryVi, 'Kênh hệ thống Android');

        final googleSnap = VoiceDiagnosticsSnapshot.fromMap(<String, dynamic>{
          'activeEngineLabel': 'service:com.google.android.tts',
        });
        expect(googleSnap.readableEngineSummaryVi, 'Speech Services by Google');

        final offlineSnap = VoiceDiagnosticsSnapshot.fromMap(<String, dynamic>{
          'activeEngineLabel': 'on_device_android13',
        });
        expect(
          offlineSnap.readableEngineSummaryVi,
          'Nhận diện Offline trên máy',
        );
      },
    );
  });

  group('2. Real-Device Mic Reliability: Initializing -> VAD Guard -> Multi-Turn Append -> Engine Switch', () {
    testWidgets(
      'Acoustic RMS VAD prevents mid-speech cutoff, tapping Mic appends without wiping, and Chi tiết thu âm switches engine cleanly at 360x800 @ 112%',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final voiceDriver = _AdvancedMockVoiceDriver();
        NativeVoiceAssistantBridge.setDriverOverride(voiceDriver);
        addTearDown(voiceDriver.dispose);

        final firestore = FakeFirebaseFirestore();
        const uid = 'u_mic_pro_test';
        await firestore.collection('users').doc(uid).set({
          'email': 'mic@lifeos.vn',
          'fullName': 'Hoàng Nam',
          'onboardingCompleted': true,
        });
        await firestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_main')
            .set({
              'id': 'wallet_main',
              'ownerId': uid,
              'name': 'Ví Chính',
              'type': 'cash',
              'balanceMinor': 5000000,
              'currencyCode': 'VND',
            });

        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'mic@lifeos.vn',
            displayName: 'Hoàng Nam',
          ),
        );

        await configureDependencies(
          authOverride: auth,
          firestoreOverride: firestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
          financialClassifierOverride: FastTextClassifier(
            useWorkerIsolate: false,
          ),
        );

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        final rootCtx = tester.element(find.byType(Scaffold).first);
        rootCtx.read<ThemeBloc>().add(const TextScaleChanged(1.12));
        await tester.pumpAndSettle();

        // 1. Open Voice Smart Capture Sheet -> defaults directly to Google Speech ('google_service')!
        await tester.tap(find.byKey(const Key('home_quick_expense_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(voiceDriver.lastEngineMode, 'google_service');
        expect(voiceDriver.lastPreferSystemDialog, isFalse);
        expect(find.text('Đang mở kênh Micro tiếng Việt...'), findsOneWidget);

        // 2. Hardware mic opens ('listening') -> ready prompt shown
        voiceDriver.controller.add(const VoiceStateSignal('listening'));
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Đang thu âm... Hãy nói tự nhiên'), findsOneWidget);

        // 3. Partial complete clause arrives ("Ăn phở 55 nghìn"), normally auto-stops at 850ms.
        // Simulate speaker continuing to talk (RMS = 6.8 dB at 450ms & 750ms) -> MUST NOT cut off!
        voiceDriver.controller.add(
          const VoiceTranscriptSignal(text: 'Ăn phở 55 nghìn', isFinal: false),
        );
        await tester.pump(const Duration(milliseconds: 450));
        voiceDriver.controller.add(const VoiceRmsSignal(6.8));
        await tester.pump(const Duration(milliseconds: 300));
        voiceDriver.controller.add(const VoiceRmsSignal(7.2));
        await tester.pump(const Duration(milliseconds: 250));
        // Total 1000ms (> 850ms), yet speaker was actively speaking -> stopCount MUST still be 0!
        expect(voiceDriver.stopCount, 0);

        // 4. Speaker now pauses silently -> auto-stops cleanly after ~850ms of true silence
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pumpAndSettle();
        expect(voiceDriver.stopCount, 1);

        // 5. User taps Mic button again (`voice_mic_toggle_button`) to ADD a second expense
        await tester.tap(find.byKey(const Key('voice_mic_toggle_button')));
        await tester.pump(const Duration(milliseconds: 60));
        voiceDriver.controller.add(const VoiceStateSignal('listening'));
        voiceDriver.controller.add(
          const VoiceTranscriptSignal(text: 'Cà phê 35 nghìn', isFinal: true),
        );
        await tester.pumpAndSettle();

        final textField = tester.widget<TextField>(
          find.byKey(const Key('voice_transcript_input')),
        );
        expect(
          textField.controller?.text,
          'Ăn phở 55 nghìn, Cà phê 35 nghìn',
        );

        // 6. Expand 'Chi tiết thu âm' -> ONLY Google modes shown (broken OEM/non-VN modes removed!)
        await tester.ensureVisible(
          find.byKey(const Key('voice_mic_details_toggle')),
        );
        await tester.tap(find.byKey(const Key('voice_mic_details_toggle')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('voice_mic_diagnostics_panel')),
          findsOneWidget,
        );
        expect(find.text('Quyền Micro: Đã cấp'), findsOneWidget);
        expect(find.text('Speech Services by Google'), findsOneWidget);
        expect(
          find.byKey(const Key('voice_engine_chip_google_service')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('voice_engine_chip_system_dialog')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('voice_engine_chip_auto')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('voice_engine_chip_on_device')),
          findsNothing,
        );

        await tester.ensureVisible(
          find.byKey(const Key('voice_engine_chip_system_dialog')),
        );
        await tester.tap(
          find.byKey(const Key('voice_engine_chip_system_dialog')),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(voiceDriver.lastEngineMode, 'system_dialog');
        expect(voiceDriver.lastPreferSystemDialog, isTrue);
        expect(
          await UserBehaviorPrefs.loadPreferredVoiceEngineMode(),
          'system_dialog',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Processing safety guard rescues OEM engines that hang in processing without emitting final results',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final voiceDriver = _AdvancedMockVoiceDriver()
          ..emitInitializingFirst = false;
        NativeVoiceAssistantBridge.setDriverOverride(voiceDriver);
        addTearDown(voiceDriver.dispose);

        final firestore = FakeFirebaseFirestore();
        const uid = 'u_mic_watchdog';
        await firestore.collection('users').doc(uid).set({
          'email': 'watchdog@lifeos.vn',
          'fullName': 'Minh Tâm',
          'onboardingCompleted': true,
        });
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'watchdog@lifeos.vn',
            displayName: 'Minh Tâm',
          ),
        );

        await configureDependencies(
          authOverride: auth,
          firestoreOverride: firestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
          financialClassifierOverride: FastTextClassifier(
            useWorkerIsolate: false,
          ),
        );

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('home_quick_expense_btn')));
        await tester.pumpAndSettle();

        // Emit incomplete partial ("Ăn trưa") + 'processing' hang (OEM never sends onResults)
        voiceDriver.controller.add(
          const VoiceTranscriptSignal(text: 'Ăn trưa', isFinal: false),
        );
        voiceDriver.controller.add(const VoiceStateSignal('processing'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Đang tự động thu âm...'), findsOneWidget);

        // After 1650ms processing safety guard fires -> exits listening hang cleanly!
        await tester.pump(const Duration(milliseconds: 1700));
        await tester.pumpAndSettle();
        expect(find.text('Đang tự động thu âm...'), findsNothing);
        expect(find.text('Kiểm tra & Xác nhận lại'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
