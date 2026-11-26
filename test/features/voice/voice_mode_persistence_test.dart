import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/features/voice_assistant/domain/entities/voice_engine_capability.dart';

void main() {
  setUp(() async {
    await UserBehaviorPrefs.resetForTest();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await UserBehaviorPrefs.resetForTest();
  });

  group('Voice Mode Persistence & Account Isolation (Finding 5)', () {
    const allModes = <String>[
      'google_service',
      'online_google',
      'system_dialog',
      'offline_strict',
      'hybrid_auto',
    ];

    test(
      'savePreferredVoiceEngineMode -> loadPreferredVoiceEngineMode round-trips EVERY mode and survives simulated app restart (guest)',
      () async {
        for (final mode in allModes) {
          await UserBehaviorPrefs.savePreferredVoiceEngineMode(mode);
          expect(UserBehaviorPrefs.cachedVoiceEngineMode, mode);
          expect(await UserBehaviorPrefs.loadPreferredVoiceEngineMode(), mode);

          // Simulate cold app restart (wipes static RAM caches, keeps persisted store)
          UserBehaviorPrefs.simulateAppRestartForTest();
          expect(
            UserBehaviorPrefs.cachedVoiceEngineMode,
            'google_service',
            reason: 'RAM cache must be cleared on restart before loading',
          );

          final reloaded =
              await UserBehaviorPrefs.loadPreferredVoiceEngineMode();
          expect(
            reloaded,
            mode,
            reason: 'Mode "$mode" must survive fresh prefs load after restart',
          );
        }
      },
    );

    test(
      'save -> reload -> simulated app restart preserves EVERY mode scoped per account without cross-account leakage',
      () async {
        final accountModes = <String, String>{
          'u_offline': 'offline_strict',
          'u_hybrid': 'hybrid_auto',
          'u_dialog': 'system_dialog',
          'u_online_alias': 'online_google',
          'u_google': 'google_service',
        };

        for (final entry in accountModes.entries) {
          UserBehaviorPrefs.bindActiveUser(entry.key);
          await UserBehaviorPrefs.savePreferredVoiceEngineMode(entry.value);
        }

        // Simulate full app restart
        UserBehaviorPrefs.simulateAppRestartForTest();

        for (final entry in accountModes.entries) {
          UserBehaviorPrefs.bindActiveUser(entry.key);
          expect(
            await UserBehaviorPrefs.loadPreferredVoiceEngineMode(),
            entry.value,
            reason: 'Account ${entry.key} must retain ${entry.value}',
          );
        }

        // Unconfigured user defaults cleanly to google_service without reading prior user's mode
        UserBehaviorPrefs.bindActiveUser('u_fresh_user');
        expect(
          await UserBehaviorPrefs.loadPreferredVoiceEngineMode(),
          'google_service',
        );
      },
    );

    test(
      'legacy wire aliases normalize deterministically and map cleanly to VoiceRecognitionPreference',
      () async {
        await UserBehaviorPrefs.savePreferredVoiceEngineMode('on_device');
        UserBehaviorPrefs.simulateAppRestartForTest();
        expect(
          await UserBehaviorPrefs.loadPreferredVoiceEngineMode(),
          'offline_strict',
        );
        expect(
          VoiceRecognitionPreference.fromWireValue(
            await UserBehaviorPrefs.loadPreferredVoiceEngineMode(),
          ),
          VoiceRecognitionPreference.offlineStrict,
        );

        await UserBehaviorPrefs.savePreferredVoiceEngineMode('auto');
        UserBehaviorPrefs.simulateAppRestartForTest();
        expect(
          await UserBehaviorPrefs.loadPreferredVoiceEngineMode(),
          'hybrid_auto',
        );
        expect(
          VoiceRecognitionPreference.fromWireValue(
            await UserBehaviorPrefs.loadPreferredVoiceEngineMode(),
          ),
          VoiceRecognitionPreference.hybridAuto,
        );
      },
    );
  });
}
