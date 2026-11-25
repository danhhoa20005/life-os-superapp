import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/config/firebase_config.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/services/android_notification_bridge.dart';
import 'package:life_os/core/services/native_app_updater_bridge.dart';
import 'package:life_os/features/app_update/data/datasources/app_update_remote_datasource.dart';
import 'package:life_os/features/app_update/domain/entities/app_update_entities.dart';
import 'package:life_os/features/calendar/data/datasources/google_calendar_api_datasource.dart';
import 'package:life_os/features/calendar/data/repositories/calendar_repository_impl.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/documents/data/repositories/document_vault_repository_impl.dart';
import 'package:life_os/features/documents/domain/entities/document_vault_entity.dart';
import 'package:life_os/features/family/data/repositories/family_repository_impl.dart';
import 'package:life_os/features/notifications/data/repositories/notifications_repository_impl.dart';

class _TestUpdaterBridge extends NativeAppUpdaterBridge {
  final String cacheDirPath;
  int installLaunchedCount = 0;

  _TestUpdaterBridge(this.cacheDirPath);

  @override
  Future<InstalledAppMeta> getInstalledAppVersion() async {
    return const InstalledAppMeta(
      versionName: '3.15.0',
      buildNumber: 30,
      packageName: 'vn.lifeos.app.life_os',
      abi: 'arm64-v8a',
    );
  }

  @override
  Future<String> getUpdateCacheDir() async => cacheDirPath;

  @override
  Future<String> installApk(String filePath) async {
    installLaunchedCount += 1;
    return 'INSTALLER_LAUNCHED';
  }
}

void main() {
  group(
    'Comprehensive Review Remediation Suite (F01–F20 / SEC / FIN / BG / APP / CAL / DOC / OPS)',
    () {
      test(
        'SEC-01..SEC-04, F05 & F06: firestore.rules enforces MapDiff join/leave isolation, blocks admin owner-override & 3rd-party settlement forgery, and deduplicates double-confirm',
        () async {
          final rules = File('firestore.rules').readAsStringSync();

          // F02 / SEC-01 & SEC-03: MapDiff isolation on voluntary leave & invite join
          expect(rules, contains('unchangedMapExceptSelfLeave'));
          expect(rules, contains('unchangedMapExceptSelfJoin'));
          expect(
            rules,
            contains(
              "affectedKeys().hasOnly(['memberIds', 'memberRoles', 'memberNames', 'updatedAt'])",
            ),
          );

          // F03 / SEC-02: Separate owner vs admin branches; admin cannot escalate self or alter owner
          expect(
            rules,
            contains("resource.data.memberRoles[request.auth.uid] == 'admin'"),
          );
          expect(
            rules,
            contains(
              "request.resource.data.memberRoles[resource.data.createdBy] == 'owner'",
            ),
          );

          // F04 / SEC-04 / AUD-002: Creditor-only direct receipt or atomic 2-step settlement_requests
          // confirmation (`stl_req_`) and deterministic single reversal (`rev_`); forbids unilateral debtor forgery
          expect(rules, contains('match /settlement_requests/{requestId}'));
          expect(
            rules,
            contains(
              "settlementId == 'stl_req_' + request.resource.data.settlementRequestId",
            ),
          );
          expect(
            rules,
            contains(
              "settlementId == 'rev_' + request.resource.data.reversalOfId",
            ),
          );

          // F05: Locked/settled split_bills cannot be mutated
          expect(
            rules,
            contains("resource.data.get('status', 'open') != 'locked'"),
          );

          // SEC-04 Runtime Idempotency: Double-confirming identical settlement produces only 1 record
          final db = FakeFirebaseFirestore();
          final famDs = FamilyRemoteDataSource(db);
          await famDs.recordDebtSettlement(
            familyId: 'fam_sec04',
            fromUserId: 'u_payer',
            fromUserName: 'Minh',
            toUserId: 'u_payee',
            toUserName: 'Lan',
            amountMinor: 150000,
            paymentCode: 'SEVQR LIFEOS SPLIT99',
          );
          await famDs.recordDebtSettlement(
            familyId: 'fam_sec04',
            fromUserId: 'u_payer',
            fromUserName: 'Minh',
            toUserId: 'u_payee',
            toUserName: 'Lan',
            amountMinor: 150000,
            paymentCode: 'SEVQR LIFEOS SPLIT99',
          );
          final settlements = await db
              .collection('families')
              .doc('fam_sec04')
              .collection('settlements')
              .get();
          expect(settlements.docs.length, 1);
        },
      );

      test(
        'FIN-01, FIN-02, FIN-03 & FIN-04: Distinct 50k purchases 1m apart stay separate; multi-wallet ambiguity blocks wrong auto-commit; 50 concurrent callbacks stay atomic',
        () async {
          final db = FakeFirebaseFirestore();
          final auth = MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'u_fin'),
          );
          final notifDs = NotificationsRemoteDataSource(
            firestore: db,
            firebaseAuth: auth,
            bridge: AndroidNotificationBridge(),
          );
          final baseTime = DateTime(2026, 11, 24, 10, 0);

          // Seed 2 distinct Vietcombank wallets for FIN-03 multi-account test
          await db
              .collection('users')
              .doc('u_fin')
              .collection('wallets')
              .doc('w_vcb_salary')
              .set({
                'id': 'w_vcb_salary',
                'ownerId': 'u_fin',
                'name': 'VCB Lương',
                'type': 'bank',
                'bankCode': 'VCB',
                'maskedAccount': '•••• 1111',
                'balanceMinor': 10000000,
              });
          await db
              .collection('users')
              .doc('u_fin')
              .collection('wallets')
              .doc('w_vcb_saving')
              .set({
                'id': 'w_vcb_saving',
                'ownerId': 'u_fin',
                'name': 'VCB Tiết kiệm',
                'type': 'bank',
                'bankCode': 'VCB',
                'maskedAccount': '•••• 2222',
                'balanceMinor': 20000000,
              });

          await notifDs.updateConsent(
            userId: 'u_fin',
            enabled: true,
            allowedPackages: const ['com.VCB'],
            autoConfirmSignals: true,
          );

          // FIN-01: Two 50,000đ purchases on account 1111 separated by 1 minute MUST remain 2 transactions!
          await notifDs.ingestAndroidNotification(
            userId: 'u_fin',
            defaultWalletId: 'w_vcb_salary',
            packageName: 'com.VCB',
            title: 'VCB Digibank',
            body:
                'TK 0071***1111 GD: -50.000VND. ND: Mua ca phe ly 1. SD: 9.950.000VND',
            postedAt: baseTime,
            notificationId: 'n_50k_1',
          );
          await notifDs.ingestAndroidNotification(
            userId: 'u_fin',
            defaultWalletId: 'w_vcb_salary',
            packageName: 'com.VCB',
            title: 'VCB Digibank',
            body:
                'TK 0071***1111 GD: -50.000VND. ND: Mua banh mi ly 2. SD: 9.900.000VND',
            postedAt: baseTime.add(const Duration(minutes: 1)),
            notificationId: 'n_50k_2',
          );

          final txsAfterFin01 = await db
              .collection('users')
              .doc('u_fin')
              .collection('transactions')
              .get();
          expect(txsAfterFin01.docs.length, 2);

          // FIN-03: Notification WITHOUT accountTail when user has 2 VCB wallets MUST NOT auto-commit to wrong wallet!
          await notifDs.ingestAndroidNotification(
            userId: 'u_fin',
            defaultWalletId: 'w_vcb_salary',
            packageName: 'com.VCB',
            title: 'VCB Digibank',
            body: 'So du TK VCB thay doi -120.000VND luc 10:05 tai Sieu thi',
            postedAt: baseTime.add(const Duration(minutes: 5)),
            notificationId: 'n_ambiguous_vcb',
          );

          final ambiguousSnap = await db
              .collection('users')
              .doc('u_fin')
              .collection('transactions')
              .where(
                'reconciliationStatus',
                isEqualTo: 'ambiguous_wallet_needs_review',
              )
              .get();
          expect(ambiguousSnap.docs.length, 1);
          expect(
            ambiguousSnap.docs.single.data()['verification'],
            'needsReview',
          );
          expect(ambiguousSnap.docs.single.data()['ledgerApplied'], isFalse);

          // Wallet 1111 balance stayed 9,900,000 (NOT deducted by ambiguous signal!)
          final w1Snap = await db
              .collection('users')
              .doc('u_fin')
              .collection('wallets')
              .doc('w_vcb_salary')
              .get();
          expect(w1Snap.data()!['balanceMinor'], 9900000);

          // FIN-04: 50 concurrent duplicate verified callbacks only create 1 canonical transaction!
          await Future.wait(
            List.generate(
              50,
              (_) => notifDs.ingestVerifiedBankFeedEvent(
                userId: 'u_fin',
                walletId: 'w_vcb_saving',
                externalTransactionId: 'SEPAY_BURST_777',
                direction: 'credit',
                amountMinor: 500000,
                content: 'Burst concurrency test',
                occurredAt: baseTime.add(const Duration(minutes: 10)),
                referenceCode: 'FT_BURST_777',
              ),
            ),
          );

          final burstTxs = await db
              .collection('users')
              .doc('u_fin')
              .collection('transactions')
              .where('externalTransactionId', isEqualTo: 'SEPAY_BURST_777')
              .get();
          expect(burstTxs.docs.length, 1);
          final w2Snap = await db
              .collection('users')
              .doc('u_fin')
              .collection('wallets')
              .doc('w_vcb_saving')
              .get();
          expect(w2Snap.data()!['balanceMinor'], 20500000);
        },
      );

      test(
        'BG-01: 120 background notifications survive mid-drain crash before ACK and commit 100% without loss or duplication',
        () async {
          final db = FakeFirebaseFirestore();
          final auth = MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'u_bg01'),
          );
          final bridge = AndroidNotificationBridge();
          final notifDs = NotificationsRemoteDataSource(
            firestore: db,
            firebaseAuth: auth,
            bridge: bridge,
          );
          await notifDs.updateConsent(
            userId: 'u_bg01',
            enabled: true,
            allowedPackages: const ['com.MBmobile'],
          );

          final startMs = DateTime(2026, 11, 24, 8, 0).millisecondsSinceEpoch;
          for (var i = 0; i < 120; i++) {
            bridge.simulateBackgroundBankSignal(
              notificationKey: 'bg_key_$i',
              packageName: 'com.MBmobile',
              title: 'MB Bank',
              body: 'TK 09***8888 GD: -${15000 + i * 1000}VND tai Cua hang #$i',
              postedAtEpochMs: startMs + i * 1000,
            );
          }
          expect(bridge.debugPendingUnacknowledgedCount, 120);

          // Simulate crash after draining & committing only the first 45 items!
          final firstDrain = await notifDs.drainQueuedNativeSignals();
          expect(firstDrain.length, 120);
          for (var i = 0; i < 45; i++) {
            final item = firstDrain[i];
            await notifDs.ingestAndroidNotification(
              userId: 'u_bg01',
              defaultWalletId: 'wallet_cash_default',
              packageName: item['packageName'] as String,
              title: item['title'] as String,
              body: item['body'] as String,
              postedAt: DateTime.fromMillisecondsSinceEpoch(
                item['postedAtEpochMs'] as int,
              ),
              notificationId: item['notificationKey'] as String,
            );
          }
          // 75 unacknowledged items remain safely in durable queue!
          expect(bridge.debugPendingUnacknowledgedCount, 75);

          // App restarts and drains remaining items -> all 120 committed, 0 lost, 0 duplicated!
          final retryDrain = await notifDs.drainQueuedNativeSignals();
          expect(retryDrain.length, 75);
          for (final item in retryDrain) {
            await notifDs.ingestAndroidNotification(
              userId: 'u_bg01',
              defaultWalletId: 'wallet_cash_default',
              packageName: item['packageName'] as String,
              title: item['title'] as String,
              body: item['body'] as String,
              postedAt: DateTime.fromMillisecondsSinceEpoch(
                item['postedAtEpochMs'] as int,
              ),
              notificationId: item['notificationKey'] as String,
            );
          }

          expect(bridge.debugPendingUnacknowledgedCount, 0);
          final allCommitted = await db
              .collection('users')
              .doc('u_bg01')
              .collection('transactions')
              .get();
          expect(allCommitted.docs.length, 120);
        },
      );

      test(
        'APP-01, APP-02, F15 & OPS-01: Mandatory OTA SHA-256 rejects tampered same-size cache, blocks missing hash/untrusted URL, gates release signing & blocks production Emulator fallback',
        () async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          final tempDir = await Directory.systemTemp.createTemp(
            'lifeos_ota_test_',
          );
          addTearDown(() async {
            debugDefaultTargetPlatformOverride = null;
            if (tempDir.existsSync()) {
              await tempDir.delete(recursive: true);
            }
          });

          final validApkBytes = utf8.encode(
            'VALID_SIGNED_APK_PAYLOAD_BINARY_CONTENT_2026',
          );
          final validSha256 = sha256.convert(validApkBytes).toString();
          final tamperedSameSizeBytes = utf8.encode(
            'TAMPERED_MALICIOUS_PAYLOAD_SAME_LENGTH_2026!',
          );
          expect(tamperedSameSizeBytes.length, validApkBytes.length);

          // Pre-populate cache with tampered APK of the EXACT SAME byte size (APP-01)!
          final cachedFile = File('${tempDir.path}/life-os-3.16.0.apk');
          await cachedFile.writeAsBytes(tamperedSameSizeBytes);

          final bridge = _TestUpdaterBridge(tempDir.path);
          final dsBadDownload = AppUpdateRemoteDataSource(
            firestore: FakeFirebaseFirestore(),
            updaterBridge: bridge,
            httpClient: MockClient(
              (_) async => http.Response.bytes(tamperedSameSizeBytes, 200),
            ),
          );

          final validManifest = AppReleaseManifest(
            latestVersion: '3.16.0',
            latestBuildNumber: 31,
            minSupportedVersion: '1.0.0',
            releaseTitle: 'Life OS v3.16.0',
            changelog: const ['Security hardening'],
            apkDownloadUrl:
                'https://github.com/danhhoa20005/life-os-superapp/releases/download/v3.16.0/app.apk',
            htmlReleaseUrl: AppUpdateRemoteDataSource.defaultGithubReleasesUrl,
            apkSizeBytes: validApkBytes.length,
            apkSha256: validSha256,
            publishedAt: DateTime(2026, 11, 24),
            sourceName: 'GitHub Releases',
          );

          // APP-01: Tampered same-size cache is NOT installed; re-download also tampered -> throws OTA_CHECKSUM_MISMATCH!
          await expectLater(
            dsBadDownload.downloadAndInstall(validManifest).drain<void>(),
            throwsA(
              isA<AppException>().having(
                (e) => e.code,
                'code',
                'OTA_CHECKSUM_MISMATCH',
              ),
            ),
          );
          expect(bridge.installLaunchedCount, 0);
          expect(cachedFile.existsSync(), isFalse);

          // Missing SHA-256 manifest is blocked fail-closed (OTA_MISSING_CHECKSUM)!
          final noHashManifest = AppReleaseManifest(
            latestVersion: '3.16.0',
            latestBuildNumber: 31,
            minSupportedVersion: '1.0.0',
            releaseTitle: 'No Hash',
            changelog: const ['Test'],
            apkDownloadUrl:
                'https://github.com/danhhoa20005/life-os-superapp/releases/download/v3.16.0/app.apk',
            htmlReleaseUrl: AppUpdateRemoteDataSource.defaultGithubReleasesUrl,
            publishedAt: DateTime(2026, 11, 24),
            sourceName: 'GitHub Releases',
          );
          await expectLater(
            dsBadDownload.downloadAndInstall(noHashManifest).drain<void>(),
            throwsA(
              isA<AppException>().having(
                (e) => e.code,
                'code',
                'OTA_MISSING_CHECKSUM',
              ),
            ),
          );

          // Untrusted non-HTTPS / rogue host URL is blocked fail-closed (OTA_UNTRUSTED_ORIGIN)!
          final rogueManifest = AppReleaseManifest(
            latestVersion: '3.16.0',
            latestBuildNumber: 31,
            minSupportedVersion: '1.0.0',
            releaseTitle: 'Rogue Host',
            changelog: const ['Test'],
            apkDownloadUrl: 'https://evil-mirror.example.com/life-os.apk',
            htmlReleaseUrl: AppUpdateRemoteDataSource.defaultGithubReleasesUrl,
            apkSha256: validSha256,
            publishedAt: DateTime(2026, 11, 24),
            sourceName: 'Rogue',
          );
          await expectLater(
            dsBadDownload.downloadAndInstall(rogueManifest).drain<void>(),
            throwsA(
              isA<AppException>().having(
                (e) => e.code,
                'code',
                'OTA_UNTRUSTED_ORIGIN',
              ),
            ),
          );

          // Valid SHA-256 passes verification & launches installer cleanly!
          final dsValidDownload = AppUpdateRemoteDataSource(
            firestore: FakeFirebaseFirestore(),
            updaterBridge: bridge,
            httpClient: MockClient(
              (_) async => http.Response.bytes(validApkBytes, 200),
            ),
          );
          await dsValidDownload.downloadAndInstall(validManifest).drain<void>();
          expect(bridge.installLaunchedCount, 1);

          // APP-02 & OPS-01: Gradle release signing gate & Production Emulator block
          final gradle = File(
            'android/app/build.gradle.kts',
          ).readAsStringSync();
          expect(gradle, contains('LIFEOS_REQUIRE_RELEASE_SIGNING'));
          expect(gradle, contains('GradleException'));

          expect(
            FirebaseConfig.canUseEmulatorFor(
              isReleaseBuild: true,
              explicitEmulatorFlag: true,
              projectId: 'demo-life-os',
            ),
            isFalse,
          );
          expect(
            FirebaseConfig.canUseEmulatorFor(
              isReleaseBuild: false,
              explicitEmulatorFlag: false,
              projectId: 'life-os-vn-2026',
            ),
            isFalse,
          );
        },
      );

      test(
        'CAL-01, CAL-02 & DOC-01: Google Calendar 401/offline delete preserves local events; zero signInWithPopup in Calendar OAuth; Document Vault distinguishes local-only binary',
        () async {
          // CAL-01: Simulate 401/offline failure when deleting a Google-linked calendar
          final db = FakeFirebaseFirestore();
          final failingGoogleApi = GoogleCalendarApiDataSource(
            firebaseAuth: MockFirebaseAuth(),
            tokenProviderOverride: ({required interactive}) async =>
                'tok_expired',
            httpClient: MockClient(
              (_) async => http.Response('Unauthorized', 401),
            ),
          );
          final calRemote = CalendarRemoteDataSource(
            db,
            googleApi: failingGoogleApi,
          );

          const linkedCal = ManagedCalendarEntity(
            id: 'cal_work_gcal',
            ownerId: 'u_cal',
            summary: 'Lịch Công ty',
            colorHex: '#2563EB',
            googleCalendarId: 'work_123@group.calendar.google.com',
          );
          await db
              .collection('users')
              .doc('u_cal')
              .collection('calendars')
              .doc(linkedCal.id)
              .set({'id': linkedCal.id, 'summary': linkedCal.summary});
          await db
              .collection('users')
              .doc('u_cal')
              .collection('private_events')
              .doc('ev_important')
              .set({
                'id': 'ev_important',
                'ownerId': 'u_cal',
                'calendarId': linkedCal.id,
                'title': 'Họp Hội đồng',
              });

          await expectLater(
            () =>
                calRemote.deleteCalendar(userId: 'u_cal', calendar: linkedCal),
            throwsA(
              isA<AppException>().having(
                (e) => e.code,
                'code',
                'CALENDAR_REMOTE_DELETE_FAILED',
              ),
            ),
          );

          // Local calendar & private event MUST still exist and be marked pendingRemoteDelete!
          final calDoc = await db
              .collection('users')
              .doc('u_cal')
              .collection('calendars')
              .doc(linkedCal.id)
              .get();
          expect(calDoc.exists, isTrue);
          expect(calDoc.data()!['pendingRemoteDelete'], isTrue);
          final evDoc = await db
              .collection('users')
              .doc('u_cal')
              .collection('private_events')
              .doc('ev_important')
              .get();
          expect(evDoc.exists, isTrue);

          // CAL-02: GoogleCalendarApiDataSource must NEVER call signInWithPopup
          final gcalSource = File(
            'lib/features/calendar/data/datasources/google_calendar_api_datasource.dart',
          ).readAsStringSync();
          expect(gcalSource.contains('signInWithPopup'), isFalse);

          // DOC-01: DocumentVaultRepository accurately classifies local-only binary vs cloud metadata
          final docRepo = DocumentVaultRepositoryImpl(db);
          await db
              .collection('users')
              .doc('u_doc')
              .collection('documents')
              .doc('doc_local_scan')
              .set({
                'id': 'doc_local_scan',
                'ownerId': 'u_doc',
                'folder': 'important_docs',
                'title': 'Bản scan Hộ chiếu',
                'localAttachmentPath':
                    '/data/user/0/vn.lifeos/secure_doc_vault/pp.enc',
                'createdAt': DateTime(2026, 11, 24).toIso8601String(),
              });
          final docs = await docRepo.watchDocuments(userId: 'u_doc').first;
          expect(
            docs.single.storageLifecycle,
            DocumentStorageLifecycle.localDeviceOnlyBinary,
          );
          expect(docs.single.isRestorableOnNewDevice, isFalse);
          expect(docs.single.syncStatusLabelVi, contains('thiết bị gốc'));
        },
      );
    },
  );
}
