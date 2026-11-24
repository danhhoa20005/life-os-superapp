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
import 'package:life_os/core/utils/voice_utterance_completeness.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_bloc.dart';

class _NoOpDeviceCalendarDriver implements DeviceCalendarDriver {
  const _NoOpDeviceCalendarDriver();

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

class _ControllableVoiceDriver implements VoiceAssistantDriver {
  final StreamController<VoiceAssistantSignal> controller =
      StreamController<VoiceAssistantSignal>.broadcast();
  int startCount = 0;
  int stopCount = 0;

  @override
  bool get isSupportedPlatform => true;

  @override
  Future<String> startListening() async {
    startCount++;
    controller.add(const VoiceStateSignal('listening'));
    return 'LISTENING_STARTED';
  }

  @override
  Future<void> stopListening() async {
    stopCount++;
  }

  @override
  Stream<VoiceAssistantSignal> watchSignals() => controller.stream;

  Future<void> dispose() async {
    await controller.close();
  }
}

void main() {
  setUp(() {
    NativeDeviceCalendarBridge.setDriverOverride(
      const _NoOpDeviceCalendarDriver(),
    );
  });

  tearDown(() async {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    NativeVoiceAssistantBridge.setDriverOverride(null);
    await sl.reset();
  });

  group('1. VoiceUtteranceEvaluator Smart Completeness Engine', () {
    test('Distinguishes mid-sentence pauses from semantically complete commands', () {
      // Mid-sentence without amount -> patient window, NOT readyComplete
      final incomplete1 = VoiceUtteranceEvaluator.evaluate(
        'Ăn phở bò',
        currentUserId: 'u1',
        currentUserName: 'Hòa',
      );
      expect(incomplete1.stage, VoiceReadinessStage.speakingIncomplete);
      expect(incomplete1.isReadyComplete, isFalse);
      expect(
        incomplete1.silenceAutoStopDelay.inMilliseconds,
        greaterThanOrEqualTo(2000),
      );

      // Dangling trailing connector ("và") -> speaker is adding another item
      final dangling = VoiceUtteranceEvaluator.evaluate(
        'Ăn phở 55 nghìn và',
        currentUserId: 'u1',
        currentUserName: 'Hòa',
      );
      expect(dangling.hasDanglingConnector, isTrue);
      expect(dangling.isReadyComplete, isFalse);

      // Bare small digits ("55") -> waits slightly longer in case speaker says "nghìn"
      final bareNumber = VoiceUtteranceEvaluator.evaluate(
        'Ăn phở 55',
        currentUserId: 'u1',
        currentUserName: 'Hòa',
      );
      expect(bareNumber.isReadyComplete, isFalse);

      // Complete valid financial utterance -> readyComplete with fast 850ms endpoint!
      final readyExpense = VoiceUtteranceEvaluator.evaluate(
        'Ăn phở 55 nghìn',
        currentUserId: 'u1',
        currentUserName: 'Hòa',
      );
      expect(readyExpense.isReadyComplete, isTrue);
      expect(readyExpense.silenceAutoStopDelay.inMilliseconds, 850);

      // Complete valid hydration & calendar utterances -> readyComplete!
      final readyWater = VoiceUtteranceEvaluator.evaluate(
        'Uống 300ml nước lọc',
        currentUserId: 'u1',
        currentUserName: 'Hòa',
      );
      expect(readyWater.isReadyComplete, isTrue);

      final readySplit = VoiceUtteranceEvaluator.evaluate(
        'Ăn lẩu bò 450 nghìn chia đều 3 người',
        currentUserId: 'u1',
        currentUserName: 'Hòa',
      );
      expect(readySplit.isReadyComplete, isTrue);
    });
  });

  group('2. 1-Tap Auto-Record, Smart Auto-Endpoint & Confirmation Flow', () {
    testWidgets('Tapping Mic on Home immediately starts recording, waits through incomplete words, auto-stops when complete, and saves ONLY upon user confirmation', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final voiceDriver = _ControllableVoiceDriver();
      NativeVoiceAssistantBridge.setDriverOverride(voiceDriver);
      addTearDown(voiceDriver.dispose);

      final firestore = FakeFirebaseFirestore();
      const uid = 'u_voice_test';
      await firestore.collection('users').doc(uid).set({
        'email': 'voice@lifeos.vn',
        'fullName': 'Minh Khoa',
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
            'name': 'Ví Tiền mặt',
            'type': 'cash',
            'balanceMinor': 2000000,
            'currencyCode': 'VND',
          });

      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: uid,
          email: 'voice@lifeos.vn',
          displayName: 'Minh Khoa',
        ),
      );

      await configureDependencies(
        authOverride: auth,
        firestoreOverride: firestore,
        httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
        googleCalendarTokenOverride: ({required interactive}) async => null,
        financialClassifierOverride: FastTextClassifier(useWorkerIsolate: false),
      );

      await tester.pumpWidget(const LifeOsApp());
      await tester.pumpAndSettle();

      final rootCtx = tester.element(find.byType(Scaffold).first);
      rootCtx.read<ThemeBloc>().add(const TextScaleChanged(1.12));
      await tester.pumpAndSettle();

      // 1. Tap 'Nói ghi nhanh' (Mic button on TodayPage) -> starts recording IMMEDIATELY in 1 tap!
      await tester.tap(find.byKey(const Key('home_quick_expense_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(voiceDriver.startCount, 1);
      expect(find.text('Đang tự động thu âm...'), findsOneWidget);

      // 2. Partial incomplete speech ("Ăn phở") -> does NOT cut off after 900ms!
      voiceDriver.controller.add(
        const VoiceTranscriptSignal(text: 'Ăn phở', isFinal: false),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 950));
      expect(voiceDriver.stopCount, 0);

      // 3. Speaker finishes with complete amount ("Ăn phở 55 nghìn") -> auto-stops after ~850ms!
      voiceDriver.controller.add(
        const VoiceTranscriptSignal(text: 'Ăn phở 55 nghìn', isFinal: false),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.textContaining('Đã nhận diện chuẩn'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      expect(voiceDriver.stopCount, greaterThanOrEqualTo(1));
      expect(find.text('Kiểm tra & Xác nhận lại'), findsOneWidget);
      expect(
        find.byKey(const Key('voice_confirmation_preview_card')),
        findsOneWidget,
      );
      expect(find.text('Xác nhận & Lưu'), findsOneWidget);
      expect(find.text('Nói lại'), findsOneWidget);

      // Verify NOTHING was saved yet before user confirms!
      final txListBloc = rootCtx.read<TransactionListBloc>();
      expect(txListBloc.state.allTransactions, isEmpty);

      // 4. User taps 'Nói lại' -> clears and restarts recording immediately!
      await tester.ensureVisible(find.byKey(const Key('voice_retry_bottom_button')));
      await tester.tap(find.byKey(const Key('voice_retry_bottom_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(voiceDriver.startCount, 2);

      // 5. Speaker says "Đổ xăng 70 nghìn" -> auto-stops -> user taps 'Xác nhận & Lưu' -> saved!
      voiceDriver.controller.add(
        const VoiceTranscriptSignal(text: 'Đổ xăng 70 nghìn', isFinal: false),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('confirm_voice_analysis_button')),
      );
      await tester.tap(find.byKey(const Key('confirm_voice_analysis_button')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        txListBloc.state.allTransactions.any((tx) => tx.amountMinor == 70000),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    test(
      'Session token isolation prevents a closing sheet dispose() from cancelling a newly started voice session',
      () async {
        final driver = _ControllableVoiceDriver();
        NativeVoiceAssistantBridge.setDriverOverride(driver);
        addTearDown(driver.dispose);

        const bridge = NativeVoiceAssistantBridge();
        await bridge.startListening(sessionToken: 'sheet_session_1');
        expect(driver.startCount, 1);

        // User opens a second voice session while sheet 1 is still animating closed
        await bridge.startListening(sessionToken: 'sheet_session_2');
        expect(driver.startCount, 2);

        // Sheet 1's dispose() fires late -> MUST NOT stop sheet 2's active recording!
        await bridge.cancelListening(sessionToken: 'sheet_session_1');
        expect(driver.stopCount, 0);

        // Sheet 2's dispose() fires -> cleanly stops session 2
        await bridge.cancelListening(sessionToken: 'sheet_session_2');
        expect(driver.stopCount, 1);

        // Verify raw event parser handles permission & state payloads accurately
        final permErr = MethodChannelVoiceAssistantDriver.parseRawVoiceEvent({
          'type': 'error',
          'code': 'PERMISSION_PERMANENTLY_DENIED',
          'message': 'Quyền Micro bị tắt',
        });
        expect(permErr, isA<VoiceErrorSignal>());
        expect((permErr as VoiceErrorSignal).isPermissionError, isTrue);
        expect(permErr.isPermanentlyDenied, isTrue);
      },
    );

    testWidgets(
      'Permission denial transitions cleanly out of listening state and renders 1-tap Mic Settings & System Voice Dialog recovery buttons',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final voiceDriver = _ControllableVoiceDriver();
        NativeVoiceAssistantBridge.setDriverOverride(voiceDriver);
        addTearDown(voiceDriver.dispose);

        final firestore = FakeFirebaseFirestore();
        const uid = 'u_voice_perm';
        await firestore.collection('users').doc(uid).set({
          'email': 'perm_voice@lifeos.vn',
          'fullName': 'Ngọc Anh',
          'onboardingCompleted': true,
        });
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'perm_voice@lifeos.vn',
            displayName: 'Ngọc Anh',
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

        // Simulate Android OS denying RECORD_AUDIO permission -> must NOT freeze in listening state!
        voiceDriver.controller.add(const VoiceStateSignal('idle'));
        voiceDriver.controller.add(
          const VoiceErrorSignal(
            'Chưa cấp quyền Micro để thu âm trực tiếp.',
            code: 'PERMISSION_PERMANENTLY_DENIED',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Đang tự động thu âm...'), findsNothing);
        expect(
          find.byKey(const Key('voice_grant_mic_permission_btn')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('voice_system_dialog_fallback_btn')),
          findsOneWidget,
        );

        // Tapping 'Thu âm hệ thống' launches system fallback cleanly
        await tester.tap(
          find.byKey(const Key('voice_system_dialog_fallback_btn')),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(voiceDriver.startCount, 2);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
