import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/services/android_notification_bridge.dart';
import 'package:life_os/core/services/native_alarm_scheduler_bridge.dart';
import 'package:life_os/core/services/native_app_updater_bridge.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/services/native_home_widget_bridge.dart';
import 'package:life_os/core/services/native_privacy_screen_bridge.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/services/native_voice_assistant_bridge.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/features/app_update/data/datasources/app_update_remote_datasource.dart';
import 'package:life_os/features/app_update/domain/entities/app_update_entities.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_bloc.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_event.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_state.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/notifications/data/repositories/notifications_repository_impl.dart';
import 'package:life_os/features/notifications/domain/entities/notification_entities.dart';
import 'package:mocktail/mocktail.dart';

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

class _FsmVoiceDriver implements AdvancedVoiceAssistantDriver {
  final StreamController<VoiceAssistantSignal> controller =
      StreamController<VoiceAssistantSignal>.broadcast();
  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;
  String? lastSessionToken;
  String? lastCancelledToken;

  @override
  bool get isSupportedPlatform => true;

  @override
  Future<String> startListening() => startListeningSession();

  @override
  Future<String> startListeningSession({
    String? sessionToken,
    bool preferSystemDialog = false,
    String engineMode = 'auto',
    bool forceInlineProbe = false,
  }) async {
    startCount++;
    lastSessionToken = sessionToken;
    controller.add(
      VoiceStateSignal('listening', sessionToken: sessionToken),
    );
    return 'LISTENING_STARTED';
  }

  @override
  Future<void> stopListening() async {
    stopCount++;
  }

  @override
  Future<void> cancelListeningSession({String? sessionToken}) async {
    cancelCount++;
    lastCancelledToken = sessionToken;
    controller.add(
      VoiceStateSignal('cancelled', sessionToken: sessionToken),
    );
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
      availableEngines: <String>['service:com.google.android.tts'],
      activeEngineLabel: 'service:com.google.android.tts',
      sdkInt: 35,
      manufacturer: 'Google',
    );
  }

  @override
  Stream<VoiceAssistantSignal> watchSignals() => controller.stream;

  Future<void> dispose() async {
    await controller.close();
  }
}

class _SpyPrivacyDriver implements PrivacyScreenDriver {
  final List<bool> toggledStates = <bool>[];
  bool shouldSucceed = true;

  @override
  bool get isSupportedPlatform => true;

  @override
  Future<bool> setPrivacyScreenEnabled(bool enabled) async {
    toggledStates.add(enabled);
    return shouldSucceed;
  }
}

class _SpyHomeWidgetBridge extends NativeHomeWidgetBridge {
  int clearOnSignOutCalls = 0;

  @override
  Future<void> clearWidgetsOnSignOut() async {
    clearOnSignOutCalls += 1;
    await super.clearWidgetsOnSignOut();
  }
}

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserMetadata extends Mock implements UserMetadata {}

void main() {
  setUp(() async {
    await UserBehaviorPrefs.resetForTest();
    NativeDeviceCalendarBridge.setDriverOverride(const _NoOpCalendarDriver());
  });

  tearDown(() async {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    NativeVoiceAssistantBridge.setDriverOverride(null);
    NativePrivacyScreenBridge.setDriverOverride(null);
    debugDefaultTargetPlatformOverride = null;
    await sl.reset();
  });

  group('1. Voice Assistant 9-State FSM, Session Token & Lifecycle', () {
    test(
      'VoiceCaptureState exposes all 9 canonical FSM states, wire parsing & transition rules',
      () {
        expect(VoiceCaptureState.values.length, 9);
        expect(
          VoiceCaptureState.values,
          containsAll(const [
            VoiceCaptureState.idle,
            VoiceCaptureState.requestingPermission,
            VoiceCaptureState.initializing,
            VoiceCaptureState.listening,
            VoiceCaptureState.processing,
            VoiceCaptureState.review,
            VoiceCaptureState.completed,
            VoiceCaptureState.error,
            VoiceCaptureState.cancelled,
          ]),
        );

        for (final st in VoiceCaptureState.values) {
          expect(VoiceCaptureState.fromWireStatus(st.wireValue), st);
        }
        expect(VoiceCaptureState.fromWireStatus('canceled'), VoiceCaptureState.cancelled);

        // Valid FSM transitions
        expect(VoiceCaptureState.idle.canTransitionTo(VoiceCaptureState.requestingPermission), isTrue);
        expect(VoiceCaptureState.requestingPermission.canTransitionTo(VoiceCaptureState.initializing), isTrue);
        expect(VoiceCaptureState.initializing.canTransitionTo(VoiceCaptureState.listening), isTrue);
        expect(VoiceCaptureState.listening.canTransitionTo(VoiceCaptureState.processing), isTrue);
        expect(VoiceCaptureState.processing.canTransitionTo(VoiceCaptureState.review), isTrue);
        expect(VoiceCaptureState.review.canTransitionTo(VoiceCaptureState.completed), isTrue);
        expect(VoiceCaptureState.listening.canTransitionTo(VoiceCaptureState.cancelled), isTrue);
        expect(VoiceCaptureState.initializing.canTransitionTo(VoiceCaptureState.error), isTrue);
        expect(VoiceCaptureState.error.canTransitionTo(VoiceCaptureState.idle), isTrue);

        // Disallowed impossible jumps
        expect(VoiceCaptureState.idle.canTransitionTo(VoiceCaptureState.completed), isFalse);
        expect(VoiceCaptureState.idle.canTransitionTo(VoiceCaptureState.processing), isFalse);
      },
    );

    test(
      'parseRawVoiceEvent preserves sessionToken and watchSignals filters out stale-session events',
      () async {
        final driver = _FsmVoiceDriver();
        NativeVoiceAssistantBridge.setDriverOverride(driver);
        addTearDown(driver.dispose);

        final parsedState = MethodChannelVoiceAssistantDriver.parseRawVoiceEvent({
          'type': 'state',
          'status': 'cancelled',
          'sessionToken': 'tok_1',
        });
        expect(parsedState, isA<VoiceStateSignal>());
        expect((parsedState as VoiceStateSignal).sessionToken, 'tok_1');
        expect(parsedState.captureState, VoiceCaptureState.cancelled);

        final parsedPartial = MethodChannelVoiceAssistantDriver.parseRawVoiceEvent({
          'type': 'partial',
          'text': 'Ăn trưa',
          'sessionToken': 'tok_1',
        });
        expect((parsedPartial as VoiceTranscriptSignal).sessionToken, 'tok_1');

        final parsedErr = MethodChannelVoiceAssistantDriver.parseRawVoiceEvent({
          'type': 'error',
          'code': 'NO_MATCH',
          'message': 'Chưa nghe rõ',
          'sessionToken': 'tok_1',
        });
        expect((parsedErr as VoiceErrorSignal).sessionToken, 'tok_1');

        const bridge = NativeVoiceAssistantBridge();
        final receivedForSessionA = <VoiceAssistantSignal>[];
        final sub = bridge
            .watchSignals(sessionToken: 'session_A')
            .listen(receivedForSessionA.add);
        addTearDown(sub.cancel);

        // Stale session B events MUST be filtered out; session A & untokened pass through
        driver.controller.add(
          const VoiceTranscriptSignal(
            text: 'Stale from B',
            isFinal: true,
            sessionToken: 'session_B',
          ),
        );
        driver.controller.add(
          const VoiceErrorSignal(
            'Stale error B',
            code: 'NO_MATCH',
            sessionToken: 'session_B',
          ),
        );
        driver.controller.add(
          const VoiceTranscriptSignal(
            text: 'Valid from A',
            isFinal: true,
            sessionToken: 'session_A',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(receivedForSessionA.length, 1);
        expect(
          (receivedForSessionA.single as VoiceTranscriptSignal).text,
          'Valid from A',
        );
      },
    );

    testWidgets(
      'VoiceSmartCaptureSheet cancels mic on background lifecycle pause, debounces rapid taps (250ms) & keeps transcript editable',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final voiceDriver = _FsmVoiceDriver();
        NativeVoiceAssistantBridge.setDriverOverride(voiceDriver);
        addTearDown(voiceDriver.dispose);

        final firestore = FakeFirebaseFirestore();
        const uid = 'u_voice_fsm';
        await firestore.collection('users').doc(uid).set({
          'email': 'fsm@lifeos.vn',
          'fullName': 'Minh Anh',
          'onboardingCompleted': true,
        });
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'fsm@lifeos.vn',
            displayName: 'Minh Anh',
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

        await tester.tap(find.byKey(const Key('home_quick_expense_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(voiceDriver.startCount, 1);
        expect(find.text('Đang tự động thu âm...'), findsOneWidget);

        // Stale session event from another token MUST NOT pollute active sheet transcript!
        voiceDriver.controller.add(
          const VoiceTranscriptSignal(
            text: 'Nhiễu từ phiên cũ 999k',
            isFinal: true,
            sessionToken: 'stale_other_session',
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        final tf = tester.widget<TextField>(
          find.byKey(const Key('voice_transcript_input')),
        );
        expect(tf.controller?.text ?? '', isEmpty);

        // Emit partial speech from active session -> simulate app going to background (paused)
        voiceDriver.controller.add(
          VoiceTranscriptSignal(
            text: 'Cà phê sữa 35 nghìn',
            isFinal: false,
            sessionToken: voiceDriver.lastSessionToken,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        expect(voiceDriver.cancelCount, 1);
        expect(find.text('Đang tự động thu âm...'), findsNothing);

        // Transcript remains editable before save!
        final editableField = tester.widget<TextField>(
          find.byKey(const Key('voice_transcript_input')),
        );
        expect(editableField.readOnly, isFalse);

        // Rapid double tap within 250ms on voice_mic_toggle_button -> second tap is debounced!
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump(const Duration(milliseconds: 300));
        final beforeTapStartCount = voiceDriver.startCount;
        await tester.tap(find.byKey(const Key('voice_mic_toggle_button')));
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(find.byKey(const Key('voice_mic_toggle_button')));
        await tester.pump(const Duration(milliseconds: 40));
        expect(voiceDriver.startCount - beforeTapStartCount, 1);
        expect(voiceDriver.stopCount, 0);

        // Cleanly unmount widget tree before sl.reset() in tearDown
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  });

  group('2. Bank Notification Queue ACK Fix & Unified Sign-Out Cleanup', () {
    test(
      'blockedOtpOrSecret and blockedConsentDisabled MUST acknowledge queued notifications to prevent 30s re-offer loops',
      () async {
        final db = FakeFirebaseFirestore();
        final bridge = AndroidNotificationBridge();
        final remote = NotificationsRemoteDataSource(
          firestore: db,
          firebaseAuth: MockFirebaseAuth(),
          bridge: bridge,
        );
        const uid = 'u_bank_ack';
        await db
            .collection('users')
            .doc(uid)
            .collection('consents')
            .doc('android_notification')
            .set({
              'enabled': true,
              'allowedPackages': ['com.VCB'],
            });

        // 1. OTP / secret notification queued -> blockedOtpOrSecret MUST call acknowledgeQueuedNotification
        bridge.simulateBackgroundBankSignal(
          notificationKey: 'k_otp_1',
          packageName: 'com.VCB',
          title: 'Vietcombank',
          body: 'Ma Digital OTP xac thuc giao dich la 884422. Khong chia se ma.',
          postedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        );
        expect(bridge.debugPendingUnacknowledgedCount, 1);

        final otpOutcome = await remote.ingestAndroidNotification(
          userId: uid,
          defaultWalletId: 'w_vcb',
          packageName: 'com.VCB',
          title: 'Vietcombank',
          body: 'Ma Digital OTP xac thuc giao dich la 884422. Khong chia se ma.',
          notificationId: 'k_otp_1',
        );
        expect(otpOutcome.kind, IngestionOutcomeKind.blockedOtpOrSecret);
        expect(bridge.debugPendingUnacknowledgedCount, 0);

        // 2. Non-allowlisted / consent-disabled notification queued -> blockedConsentDisabled MUST ACK too
        bridge.simulateBackgroundBankSignal(
          notificationKey: 'k_disabled_2',
          packageName: 'com.mbmobile',
          title: 'MB Bank',
          body: '+150.000 VND TK 1234',
          postedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        );
        expect(bridge.debugPendingUnacknowledgedCount, 1);

        final disabledOutcome = await remote.ingestAndroidNotification(
          userId: uid,
          defaultWalletId: 'w_vcb',
          packageName: 'com.mbmobile',
          title: 'MB Bank',
          body: '+150.000 VND TK 1234',
          notificationId: 'k_disabled_2',
        );
        expect(disabledOutcome.kind, IngestionOutcomeKind.blockedConsentDisabled);
        expect(bridge.debugPendingUnacknowledgedCount, 0);
      },
    );

    test(
      'AuthSignOutRequested triggers unified native cleanup across widgets, bank queue/consent, alarms & prefs',
      () async {
        final notifBridge = AndroidNotificationBridge();
        notifBridge.simulateBackgroundBankSignal(
          notificationKey: 'k_signout_1',
          packageName: 'com.VCB',
          title: 'VCB',
          body: '+50.000 VND',
          postedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        );

        await NativeAlarmSchedulerBridge.instance.scheduleEventAlarm(
          eventId: 'ev_signout_1',
          title: 'Nhắc lịch',
          subtitle: 'Kiểm tra',
          eventStartsAt: DateTime.now().add(const Duration(hours: 2)),
          minutesBefore: 10,
          fullScreen: false,
        );
        expect(
          await NativeAlarmSchedulerBridge.instance.listScheduledAlarms(),
          isNotEmpty,
        );

        final spyWidgets = _SpyHomeWidgetBridge();
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: 'u_signout_1',
            email: 'signout@lifeos.vn',
            displayName: 'Thanh',
          ),
        );
        final firestore = FakeFirebaseFirestore();
        await configureDependencies(
          authOverride: auth,
          firestoreOverride: firestore,
          bridgeOverride: notifBridge,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
        );
        await sl.unregister<NativeHomeWidgetBridge>();
        sl.registerSingleton<NativeHomeWidgetBridge>(spyWidgets);

        UserBehaviorPrefs.bindActiveUser('u_signout_1');
        expect(UserBehaviorPrefs.activeUserId, 'u_signout_1');

        final authBloc = sl<AuthBloc>();
        authBloc.add(const AuthSignOutRequested());
        await expectLater(
          authBloc.stream,
          emitsThrough(
            isA<AuthState>().having(
              (s) => s.status,
              'status',
              AuthStatus.unauthenticated,
            ),
          ),
        );
        await authBloc.close();

        expect(UserBehaviorPrefs.activeUserId, isNull);
        expect(spyWidgets.clearOnSignOutCalls, greaterThanOrEqualTo(1));
        expect(notifBridge.debugLastSyncedConsentEnabled, isFalse);
        expect(notifBridge.debugLastSyncedAllowedPackages, isEmpty);
        expect(notifBridge.debugClearQueueCallCount, greaterThanOrEqualTo(1));
        expect(notifBridge.debugPendingUnacknowledgedCount, 0);
        expect(
          await NativeAlarmSchedulerBridge.instance.listScheduledAlarms(),
          isEmpty,
        );
      },
    );
  });

  group('3. Product Flavors (github vs play), FLAG_SECURE & Native Hardening', () {
    test(
      'Distribution flavor gating blocks GitHub APK OTA download/install on play flavor and allows it on github flavor',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final tempDir = await Directory.systemTemp.createTemp('lifeos_flavor_');
        addTearDown(() async {
          if (tempDir.existsSync()) await tempDir.delete(recursive: true);
        });

        final apkBytes = utf8.encode('VALID_RELEASE_APK_BINARY');
        final sha = sha256.convert(apkBytes).toString();
        final manifest = AppReleaseManifest(
          latestVersion: '3.27.0',
          latestBuildNumber: 99,
          minSupportedVersion: '1.0.0',
          releaseTitle: 'LifeOS v3.27.0',
          changelog: const ['Hardening'],
          apkDownloadUrl:
              'https://github.com/danhhoa20005/life-os-superapp/releases/download/v3.27.0/app.apk',
          htmlReleaseUrl: AppUpdateRemoteDataSource.defaultGithubReleasesUrl,
          apkSizeBytes: apkBytes.length,
          apkSha256: sha,
          publishedAt: DateTime(2026, 11, 25),
          sourceName: 'GitHub',
        );

        // Play flavor: refuses cache dir / download / installApk!
        const playBridge = NativeAppUpdaterBridge(
          fixedDistributionFlavor: 'play',
          fixedInstalledMeta: InstalledAppMeta(
            versionName: '3.26.0',
            buildNumber: 90,
            packageName: 'vn.lifeos.app.life_os',
            abi: 'arm64-v8a',
          ),
        );
        expect(await playBridge.getDistributionFlavor(), 'play');
        expect(await playBridge.isGitHubOtaEnabled(), isFalse);
        await expectLater(
          playBridge.installApk('${tempDir.path}/dummy.apk'),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              'OTA_DISABLED_PLAY_FLAVOR',
            ),
          ),
        );

        var httpDownloadCalled = false;
        final playDs = AppUpdateRemoteDataSource(
          firestore: FakeFirebaseFirestore(),
          updaterBridge: playBridge,
          httpClient: MockClient((_) async {
            httpDownloadCalled = true;
            return http.Response.bytes(apkBytes, 200);
          }),
        );
        await expectLater(
          playDs.downloadAndInstall(manifest).drain<void>(),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              'OTA_DISABLED_PLAY_FLAVOR',
            ),
          ),
        );
        expect(httpDownloadCalled, isFalse);

        // GitHub flavor: enables OTA!
        const githubBridge = NativeAppUpdaterBridge(
          fixedDistributionFlavor: 'github',
        );
        expect(await githubBridge.getDistributionFlavor(), 'github');
        expect(await githubBridge.isGitHubOtaEnabled(), isTrue);
      },
    );

    test('NativePrivacyScreenBridge toggles FLAG_SECURE cleanly and falls back safely', () async {
      // Safe no-op fallback when no Android driver override
      expect(
        await NativePrivacyScreenBridge.instance.setPrivacyScreenEnabled(true),
        isFalse,
      );

      final spyPrivacy = _SpyPrivacyDriver();
      NativePrivacyScreenBridge.setDriverOverride(spyPrivacy);
      expect(NativePrivacyScreenBridge.instance.isSupportedPlatform, isTrue);

      expect(
        await NativePrivacyScreenBridge.instance.setPrivacyScreenEnabled(true),
        isTrue,
      );
      expect(NativePrivacyScreenBridge.instance.isPrivacyScreenEnabled, isTrue);

      expect(
        await NativePrivacyScreenBridge.instance.setPrivacyScreenEnabled(false),
        isTrue,
      );
      expect(NativePrivacyScreenBridge.instance.isPrivacyScreenEnabled, isFalse);
      expect(spyPrivacy.toggledStates, [true, false]);
    });

    test('Android flavors, manifests, backup XMLs & Kotlin hardening contracts exist', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('buildConfig = true'));
      expect(gradle, contains('flavorDimensions += "distribution"'));
      expect(gradle, contains('create("github")'));
      expect(gradle, contains('create("play")'));
      expect(gradle, contains('ENABLE_GITHUB_OTA'));
      expect(gradle, contains('DISTRIBUTION_FLAVOR'));

      final mainManifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(mainManifest.contains('REQUEST_INSTALL_PACKAGES'), isFalse);
      expect(mainManifest.contains('USE_EXACT_ALARM'), isFalse);
      expect(mainManifest, contains('SCHEDULE_EXACT_ALARM'));

      final githubManifest = File(
        'android/app/src/github/AndroidManifest.xml',
      ).readAsStringSync();
      expect(githubManifest, contains('REQUEST_INSTALL_PACKAGES'));

      final playManifest = File(
        'android/app/src/play/AndroidManifest.xml',
      ).readAsStringSync();
      expect(playManifest, contains('REQUEST_INSTALL_PACKAGES'));
      expect(playManifest, contains('USE_EXACT_ALARM'));
      expect(playManifest, contains('tools:node="remove"'));

      final backupXml = File(
        'android/app/src/main/res/xml/backup_rules.xml',
      ).readAsStringSync();
      expect(backupXml, contains('lifeos_bank_signal_queue.db'));
      expect(backupXml, contains('lifeos_bank_listener_prefs.xml'));

      final extractXml = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      expect(extractXml, contains('lifeos_bank_signal_queue.db'));
      expect(extractXml, contains('lifeos_bank_listener_prefs.xml'));

      final bankListenerKt = File(
        'android/app/src/main/kotlin/vn/lifeos/app/life_os/BankNotificationListenerService.kt',
      ).readAsStringSync();
      expect(bankListenerKt, contains('LifeOsSecureVault.encryptBytes'));
      expect(bankListenerKt, contains('"bank_queue"'));
      expect(bankListenerKt, contains('MAX_ATTEMPTS = 5'));
      expect(bankListenerKt, contains('fun clearAll()'));
      expect(bankListenerKt, contains('fun clearListenerPreferences'));
      expect(bankListenerKt, contains(r'digital\\s*otp'));
      expect(bankListenerKt, contains('passcode'));

      final widgetsKt = File(
        'android/app/src/main/kotlin/vn/lifeos/app/life_os/LifeOsHomeWidgets.kt',
      ).readAsStringSync();
      expect(widgetsKt, contains('KEY_IS_SIGNED_OUT'));
      expect(widgetsKt, contains('FLAG_SECURE'));
      expect(widgetsKt, contains('override fun onStop()'));

      final mainKt = File(
        'android/app/src/main/kotlin/vn/lifeos/app/life_os/MainActivity.kt',
      ).readAsStringSync();
      expect(mainKt, contains('vn.lifeos.app/privacy_screen'));
      expect(mainKt, contains('setRecentsScreenshotEnabled(!enabled)'));
      expect(mainKt, contains('setShowWhenLocked(false)'));
      expect(mainKt, contains('setTurnScreenOn(false)'));
      expect(mainKt, contains('clearBankSignalQueue'));

      final vaultKt = File(
        'android/app/src/main/kotlin/vn/lifeos/app/life_os/LifeOsSecureVault.kt',
      ).readAsStringSync();
      expect(vaultKt, contains('@Synchronized'));
      expect(vaultKt, contains('KeyPermanentlyInvalidatedException'));
      expect(vaultKt, contains('updateAAD'));

      final alarmKt = File(
        'android/app/src/main/kotlin/vn/lifeos/app/life_os/LifeOsAlarmScheduler.kt',
      ).readAsStringSync();
      expect(alarmKt, contains('scheduleNextMedicationAlarm'));
      expect(alarmKt, contains('PREFS_HYDRATION_DAEMON'));
      expect(alarmKt, contains('PREFS_MED_DAEMON'));
      expect(alarmKt, contains('PREFS_BG_ACTIONS'));

      final calKt = File(
        'android/app/src/main/kotlin/vn/lifeos/app/life_os/LifeOsDeviceCalendar.kt',
      ).readAsStringSync();
      expect(calKt, contains('TimeZone.getTimeZone("UTC")'));
      expect(calKt, contains('"UTC"'));
    });
  });

  group('4. Account Deletion Pre-Checks, Complete Subcollection Purge & UI', () {
    test(
      'deleteAccountAndPersonalData blocks multi-member family owner BEFORE wiping any data',
      () async {
        final db = FakeFirebaseFirestore();
        final bridge = AndroidNotificationBridge();
        const uid = 'u_owner_blocked';

        await db.collection('families').doc('fam_multi').set({
          'id': 'fam_multi',
          'name': 'Nhà Minh Lan',
          'createdBy': uid,
          'memberIds': [uid, 'u_member_2'],
          'memberRoles': {uid: 'owner', 'u_member_2': 'member'},
          'memberNames': {uid: 'Minh', 'u_member_2': 'Lan'},
        });
        await db
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .doc('tx_keep')
            .set({'amountMinor': 50000});

        final remote = NotificationsRemoteDataSource(
          firestore: db,
          firebaseAuth: MockFirebaseAuth(),
          bridge: bridge,
        );

        await expectLater(
          remote.deleteAccountAndPersonalData(uid),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              'FAMILY_OWNER_TRANSFER_REQUIRED',
            ),
          ),
        );

        // Personal data MUST NOT be wiped when pre-check blocks!
        final txSnap = await db
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .get();
        expect(txSnap.docs.length, 1);
      },
    );

    test(
      'deleteAccountAndPersonalData surfaces requires-recent-login cleanly and purges ALL subcollections including monthly_summaries, automation_*, source_claims & fuel_logs',
      () async {
        final db = FakeFirebaseFirestore();
        final bridge = AndroidNotificationBridge();
        const uid = 'u_del_full';

        // 1. Verify stale session / requires-recent-login is NEVER silently swallowed
        final mockAuth = _MockFirebaseAuth();
        final mockUser = _MockUser();
        final mockMeta = _MockUserMetadata();
        when(() => mockAuth.currentUser).thenReturn(mockUser);
        when(() => mockUser.uid).thenReturn(uid);
        when(() => mockUser.metadata).thenReturn(mockMeta);
        when(
          () => mockMeta.lastSignInTime,
        ).thenReturn(DateTime.now().subtract(const Duration(minutes: 20)));

        final remoteBlockedAuth = NotificationsRemoteDataSource(
          firestore: db,
          firebaseAuth: mockAuth,
          bridge: bridge,
        );
        await expectLater(
          remoteBlockedAuth.deleteAccountAndPersonalData(uid),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              'REQUIRES_RECENT_LOGIN',
            ),
          ),
        );

        // Also verify FirebaseAuthException('requires-recent-login') from current.delete() is NOT swallowed!
        when(() => mockMeta.lastSignInTime).thenReturn(DateTime.now());
        when(() => mockUser.delete()).thenThrow(
          FirebaseAuthException(code: 'requires-recent-login'),
        );
        await expectLater(
          remoteBlockedAuth.deleteAccountAndPersonalData(uid),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              'REQUIRES_RECENT_LOGIN',
            ),
          ),
        );

        // 2. Verify complete purge when eligible (plain member or solo family + recent login)
        final uRef = db.collection('users').doc(uid);
        await uRef.set({'id': uid, 'email': 'del@lifeos.vn'});
        await uRef.collection('monthly_summaries').doc('2026-11').set({'ok': true});
        await uRef.collection('automation_rules').doc('r1').set({'ok': true});
        await uRef.collection('automation_audits').doc('a1').set({'ok': true});
        await uRef.collection('source_claims').doc('sc1').set({'ok': true});
        await uRef.collection('vehicles').doc('v1').set({'name': 'Vision'});
        await uRef
            .collection('vehicles')
            .doc('v1')
            .collection('fuel_logs')
            .doc('fl1')
            .set({'liters': 3.5});
        await uRef
            .collection('vehicles')
            .doc('v1')
            .collection('maintenances')
            .doc('m1')
            .set({'cost': 120000});

        bridge.simulateBackgroundBankSignal(
          notificationKey: 'k_del_q',
          packageName: 'com.VCB',
          title: 'VCB',
          body: '+100.000 VND',
          postedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        );
        await NativeSecureVaultBridge.instance.writeSecret(
          key: 'sepay_tok_$uid',
          value: 'secret_token_value',
        );
        UserBehaviorPrefs.bindActiveUser(uid);

        final cleanAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: uid, email: 'del@lifeos.vn'),
        );
        final remoteClean = NotificationsRemoteDataSource(
          firestore: db,
          firebaseAuth: cleanAuth,
          bridge: bridge,
        );
        await remoteClean.deleteAccountAndPersonalData(uid);

        expect((await uRef.get()).exists, isFalse);
        expect(
          await NativeSecureVaultBridge.instance.readSecret('sepay_tok_$uid'),
          isNull,
        );
        expect((await uRef.collection('monthly_summaries').get()).docs, isEmpty);
        expect((await uRef.collection('automation_rules').get()).docs, isEmpty);
        expect((await uRef.collection('automation_audits').get()).docs, isEmpty);
        expect((await uRef.collection('source_claims').get()).docs, isEmpty);
        expect(
          (await uRef
                  .collection('vehicles')
                  .doc('v1')
                  .collection('fuel_logs')
                  .get())
              .docs,
          isEmpty,
        );
        expect(
          (await uRef
                  .collection('vehicles')
                  .doc('v1')
                  .collection('maintenances')
                  .get())
              .docs,
          isEmpty,
        );
        expect(bridge.debugClearQueueCallCount, greaterThanOrEqualTo(1));
        expect(bridge.debugLastSyncedConsentEnabled, isFalse);
        expect(UserBehaviorPrefs.activeUserId, isNull);
      },
    );

    testWidgets(
      'AccountProfilePage renders Xóa tài khoản & Dữ liệu cá nhân and warns multi-member family owner cleanly at 360x800',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final db = FakeFirebaseFirestore();
        const uid = 'u_profile_del_ui';
        await db.collection('users').doc(uid).set({
          'id': uid,
          'email': 'profile_del@lifeos.vn',
          'fullName': 'Ngọc Minh',
          'onboardingCompleted': true,
        });
        await db.collection('families').doc('fam_ui_owner').set({
          'id': 'fam_ui_owner',
          'name': 'Gia Đình Nhỏ',
          'spaceType': 'family',
          'createdBy': uid,
          'memberIds': [uid, 'u_partner'],
          'memberRoles': {uid: 'owner', 'u_partner': 'member'},
          'memberNames': {uid: 'Ngọc Minh', 'u_partner': 'Lan Anh'},
          'createdAt': DateTime.now().toIso8601String(),
        });

        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'profile_del@lifeos.vn',
            displayName: 'Ngọc Minh',
          ),
        );
        await configureDependencies(
          authOverride: auth,
          firestoreOverride: db,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
          financialClassifierOverride: FastTextClassifier(
            useWorkerIsolate: false,
          ),
        );

        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.12),
            ),
            child: LifeOsApp(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_account_profile_button')));
        await tester.pumpAndSettle();

        final listScrollable = find.descendant(
          of: find.byKey(const Key('account_profile_list_view')),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        final delBtn = find.byKey(const Key('profile_delete_account_button'));
        await tester.scrollUntilVisible(delBtn, 200, scrollable: listScrollable);
        await tester.ensureVisible(delBtn);
        await tester.pumpAndSettle();

        expect(delBtn, findsOneWidget);
        expect(find.text('Xóa tài khoản & Dữ liệu cá nhân'), findsWidgets);

        await tester.tap(delBtn);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('delete_account_owner_blocked_dialog')),
          findsOneWidget,
        );
        expect(find.textContaining('Gia Đình Nhỏ'), findsOneWidget);

        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
