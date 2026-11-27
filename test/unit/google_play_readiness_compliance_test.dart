import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/security/bank_notification_parser.dart';
import 'package:life_os/core/services/android_notification_bridge.dart';
import 'package:life_os/core/services/native_app_updater_bridge.dart';
import 'package:life_os/core/widgets/lifeos_legal_policy_dialogs.dart';
import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:life_os/features/app_update/data/datasources/app_update_remote_datasource.dart';
import 'package:life_os/features/calendar/data/datasources/google_calendar_api_datasource.dart';
import 'package:life_os/features/notifications/data/repositories/notifications_repository_impl.dart';
import 'package:life_os/features/notifications/domain/entities/notification_entities.dart';

void main() {
  group('Google Play Release Readiness Compliance Verification', () {
    test(
      '1. SMS Policy Compliance: com.google.android.apps.messaging & SMS apps are excluded from catalog, stripped on migration, and blocked at parser & repository layers',
      () async {
        expect(
          kSupportedVnBanks.any(
            (b) =>
                b.packageName == 'com.google.android.apps.messaging' ||
                b.bankCode == 'SMS',
          ),
          isFalse,
        );

        expect(
          BankNotificationParser.isBlockedSmsOrMessagingPackage(
            'com.google.android.apps.messaging',
          ),
          isTrue,
        );
        expect(
          BankNotificationParser.isBlockedSmsOrMessagingPackage(
            'com.samsung.android.messaging',
          ),
          isTrue,
        );

        final sanitized = BankNotificationParser.sanitizeAllowedBankPackages([
          'com.VCB',
          'com.google.android.apps.messaging',
          'com.android.mms',
          'com.mservice.momotransfer',
        ]);
        expect(sanitized, equals(['com.VCB', 'com.mservice.momotransfer']));

        final parserOutcome = BankNotificationParser.parseAndroidNotification(
          ownerId: 'u_play_1',
          packageName: 'com.google.android.apps.messaging',
          title: 'Vietcombank',
          body: 'SD TK 0071000888686 +500,000VND luc 10:00. SD: 12,500,000VND',
        );
        expect(parserOutcome.signal, isNull);
        expect(parserOutcome.dropReason, BankSignalDropReason.nonFinancial);

        final firestore = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'u_play_1', email: 'user@lifeos.vn'),
        );
        final remote = NotificationsRemoteDataSource(
          firestore: firestore,
          firebaseAuth: auth,
          bridge: AndroidNotificationBridge(),
        );
        await remote.updateConsent(
          userId: 'u_play_1',
          enabled: true,
          allowedPackages: ['com.VCB', 'com.google.android.apps.messaging'],
        );

        final consentSnap = await firestore
            .collection('users')
            .doc('u_play_1')
            .collection('consents')
            .doc('android_notification')
            .get();
        expect(consentSnap.data()?['allowedPackages'], equals(['com.VCB']));

        final smsIngest = await remote.ingestAndroidNotification(
          userId: 'u_play_1',
          defaultWalletId: 'w_1',
          packageName: 'com.google.android.apps.messaging',
          title: 'VCB',
          body: 'TK 0071000888686 +500,000VND. SD: 12,500,000VND',
        );
        expect(smsIngest.kind, IngestionOutcomeKind.blockedConsentDisabled);

        final txSnap = await firestore
            .collection('users')
            .doc('u_play_1')
            .collection('transactions')
            .get();
        expect(txSnap.docs, isEmpty);
      },
    );

    test(
      '2. Account Deletion Compliance: deleteAccountAndPersonalData invokes server-side deleteUserAccountData Cloud Function before deleting user doc',
      () async {
        final firestore = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'u_del_play', email: 'del@lifeos.vn'),
        );
        final invokedFunctions = <String>[];
        final remote = NotificationsRemoteDataSource(
          firestore: firestore,
          firebaseAuth: auth,
          bridge: AndroidNotificationBridge(),
          functionsInvokerOverride: (fnName, payload) async {
            invokedFunctions.add('$fnName:${payload['userId']}');
            // Simulate authoritative server-side deletion (DEL-01)
            await firestore.collection('users').doc('u_del_play').delete();
            return <String, dynamic>{
              'ok': true,
              'status': 'completed',
              'verifiedClean': true,
              'authDeleted': true,
              'deletedCount': 4,
            };
          },
        );

        await firestore.collection('users').doc('u_del_play').set({
          'id': 'u_del_play',
          'email': 'del@lifeos.vn',
        });

        await remote.deleteAccountAndPersonalData('u_del_play');
        expect(invokedFunctions, contains('deleteUserAccountData:u_del_play'));
        final userDoc = await firestore
            .collection('users')
            .doc('u_del_play')
            .get();
        expect(userDoc.exists, isFalse);
      },
    );

    test(
      '3. Play Flavor OTA & OAuth Scope Compliance: Play flavor disables GitHub APK checks/prompts and Calendar requests only least-privilege calendar.events scope',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('app_config').doc('release_manifest').set({
          'latestVersion': '9.9.9',
          'latestBuildNumber': 999,
          'apkDownloadUrl':
              'https://github.com/danhhoa20005/life-os-superapp/releases/download/v9.9.9/life-os.apk',
        });

        final playUpdaterBridge = const NativeAppUpdaterBridge(
          fixedDistributionFlavor: 'play',
          fixedGitHubOtaEnabled: false,
        );
        final dataSource = AppUpdateRemoteDataSource(
          firestore: firestore,
          updaterBridge: playUpdaterBridge,
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        );

        expect(await dataSource.fetchLatestManifest(), isNull);
        expect(
          GoogleCalendarApiDataSource.calendarScopes,
          equals(const <String>[
            'https://www.googleapis.com/auth/calendar.events',
          ]),
        );
      },
    );

    test(
      '4. Public HTML Privacy Policy & Web Account Deletion files exist and contain required disclosures',
      () {
        final privacyHtml = File('web/privacy-policy.html');
        final deleteHtml = File('web/delete-account.html');
        expect(privacyHtml.existsSync(), isTrue);
        expect(deleteHtml.existsSync(), isTrue);

        final privacyText = privacyHtml.readAsStringSync();
        expect(privacyText, contains('vn.lifeos.app.life_os'));
        expect(privacyText, contains('support@lifeos.vn'));
        expect(privacyText, contains('/delete-account.html'));

        final deleteText = deleteHtml.readAsStringSync();
        expect(deleteText, contains('vn.lifeos.app.life_os'));
        expect(deleteText, contains('deleteForm'));
        expect(deleteText, contains('7 ngày làm việc'));
      },
    );

    testWidgets(
      '5. In-app Privacy Policy & Web Account Deletion dialog renders cleanly at 360x800 @ 1.25x',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.25)),
              child: LifeOsTopToastHost(child: child!),
            ),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    key: const Key('open_policy_test_btn'),
                    onPressed: () => showLifeOsPrivacyPolicyDialog(ctx),
                    child: const Text('Open Policy'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('open_policy_test_btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('lifeos_privacy_policy_dialog')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('copy_privacy_policy_url_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('copy_account_deletion_url_button')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
