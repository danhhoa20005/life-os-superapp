import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/services/android_notification_bridge.dart';
import 'package:life_os/core/services/fcm_banking_messaging_service.dart';
import 'package:life_os/features/notifications/data/repositories/notifications_repository_impl.dart';
import 'package:life_os/features/notifications/domain/entities/notification_entities.dart';
import 'package:life_os/features/transactions/data/datasources/transaction_remote_datasource.dart';

class _TestFcmDriver implements FcmPlatformDriver {
  String currentToken = 'fcm_device_token_user_a';
  bool permissionGranted = true;
  bool unregisteredCalled = false;
  IncomingBankingPushPayload? coldStartMessage;

  final StreamController<String> registeredCtrl =
      StreamController<String>.broadcast();
  final StreamController<IncomingBankingPushPayload> foregroundCtrl =
      StreamController<IncomingBankingPushPayload>.broadcast();
  final StreamController<IncomingBankingPushPayload> openedAppCtrl =
      StreamController<IncomingBankingPushPayload>.broadcast();

  @override
  Future<bool> requestPushPermission() async => permissionGranted;

  @override
  Future<void> registerDevice() async {
    registeredCtrl.add(currentToken);
  }

  @override
  Future<void> unregisterDevice() async {
    unregisteredCalled = true;
  }

  @override
  Stream<String> get onRegistered => registeredCtrl.stream;

  @override
  Stream<IncomingBankingPushPayload> get onForegroundMessage =>
      foregroundCtrl.stream;

  @override
  Stream<IncomingBankingPushPayload> get onMessageOpenedApp =>
      openedAppCtrl.stream;

  @override
  Future<IncomingBankingPushPayload?> getInitialTerminatedMessage() async {
    final msg = coldStartMessage;
    coldStartMessage = null;
    return msg;
  }

  Future<void> dispose() async {
    await registeredCtrl.close();
    await foregroundCtrl.close();
    await openedAppCtrl.close();
  }
}

void main() {
  group(
    'Flutter Real-Time Banking, Single-Balance Reconciliation & FCM Suite (T05..T24)',
    () {
      test(
        'T05 & T24 — Cross-source reconciliation (provisional -> verified AND userConfirmed -> verified) NEVER double-adds balance',
        () async {
          final db = FakeFirebaseFirestore();
          final auth = MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'u_bank'),
          );
          final txDs = TransactionRemoteDataSource(db);
          final notifDs = NotificationsRemoteDataSource(
            firestore: db,
            firebaseAuth: auth,
            bridge: AndroidNotificationBridge(),
          );

          final now = DateTime(2026, 11, 23, 10, 0);
          await db
              .collection('users')
              .doc('u_bank')
              .collection('wallets')
              .doc('w_vcb')
              .set({
                'id': 'w_vcb',
                'ownerId': 'u_bank',
                'name': 'Vietcombank',
                'type': 'bank',
                'balanceMinor': 10000000,
                'isEstimatedBalance': true,
              });

          await notifDs.updateConsent(
            userId: 'u_bank',
            enabled: true,
            allowedPackages: const ['com.VCB'],
            autoConfirmSignals: false,
          );

          final out1 = await notifDs.ingestAndroidNotification(
            userId: 'u_bank',
            defaultWalletId: 'w_vcb',
            packageName: 'com.VCB',
            title: 'VCB Digibank',
            body:
                'TK 1017***8888 GD: +500.000VND 23/11/2026 10:00. ND: NGUYEN VAN A chuyen tien',
            postedAt: now,
          );
          expect(out1.kind, IngestionOutcomeKind.createdProvisional);
          expect(
            (await db
                    .collection('users')
                    .doc('u_bank')
                    .collection('wallets')
                    .doc('w_vcb')
                    .get())
                .data()!['balanceMinor'],
            10000000,
          );

          await txDs.decideProvisionalTransaction(
            userId: 'u_bank',
            transactionId: out1.transactionId!,
            approve: true,
          );
          expect(
            (await db
                    .collection('users')
                    .doc('u_bank')
                    .collection('wallets')
                    .doc('w_vcb')
                    .get())
                .data()!['balanceMinor'],
            10500000,
          );

          final ver1 = await notifDs.ingestVerifiedBankFeedEvent(
            userId: 'u_bank',
            walletId: 'w_vcb',
            externalTransactionId: '92704',
            direction: 'credit',
            amountMinor: 500000,
            content: 'NGUYEN VAN A chuyen tien',
            occurredAt: now.add(const Duration(minutes: 2)),
            referenceCode: 'FT24012345678',
            accumulatedBalanceMinor: 0,
          );
          expect(ver1.transactionId, out1.transactionId);

          final allTxs = await db
              .collection('users')
              .doc('u_bank')
              .collection('transactions')
              .get();
          expect(allTxs.docs.length, 1);
          expect(allTxs.docs.single.data()['verification'], 'verified');
          expect(allTxs.docs.single.data()['externalTransactionId'], '92704');
          expect(
            (await db
                    .collection('users')
                    .doc('u_bank')
                    .collection('wallets')
                    .doc('w_vcb')
                    .get())
                .data()!['balanceMinor'],
            10500000,
          );
        },
      );

      test(
        'T06, T17 & T19 — Distinct referenceCodes within 2m stay separate; unconsented & OTP signals blocked',
        () async {
          final db = FakeFirebaseFirestore();
          final auth = MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'u_t06'),
          );
          final notifDs = NotificationsRemoteDataSource(
            firestore: db,
            firebaseAuth: auth,
            bridge: AndroidNotificationBridge(),
          );
          final now = DateTime(2026, 11, 23, 11, 0);

          await db
              .collection('users')
              .doc('u_t06')
              .collection('wallets')
              .doc('w_1')
              .set({
                'id': 'w_1',
                'ownerId': 'u_t06',
                'name': 'Ví chính',
                'type': 'bank',
                'balanceMinor': 1000000,
              });

          final unconsented = await notifDs.ingestAndroidNotification(
            userId: 'u_t06',
            defaultWalletId: 'w_1',
            packageName: 'com.VCB',
            title: 'VCB',
            body: 'GD: +100.000VND',
            postedAt: now,
          );
          expect(unconsented.kind, IngestionOutcomeKind.blockedConsentDisabled);

          await notifDs.updateConsent(
            userId: 'u_t06',
            enabled: true,
            allowedPackages: const ['com.VCB'],
          );

          final otpBlocked = await notifDs.ingestAndroidNotification(
            userId: 'u_t06',
            defaultWalletId: 'w_1',
            packageName: 'com.VCB',
            title: 'VCB Smart OTP',
            body:
                'Ma xac thuc OTP giao dich 100.000VND cua quy khach la 839201',
            postedAt: now,
          );
          expect(otpBlocked.kind, IngestionOutcomeKind.blockedOtpOrSecret);

          await notifDs.ingestVerifiedBankFeedEvent(
            userId: 'u_t06',
            walletId: 'w_1',
            externalTransactionId: '1001',
            direction: 'credit',
            amountMinor: 150000,
            content: 'Khach 1 chuyen',
            occurredAt: now,
            referenceCode: 'FT_AAA',
          );
          await notifDs.ingestVerifiedBankFeedEvent(
            userId: 'u_t06',
            walletId: 'w_1',
            externalTransactionId: '1002',
            direction: 'credit',
            amountMinor: 150000,
            content: 'Khach 2 chuyen',
            occurredAt: now.add(const Duration(minutes: 1)),
            referenceCode: 'FT_BBB',
          );

          final txs = await db
              .collection('users')
              .doc('u_t06')
              .collection('transactions')
              .get();
          expect(txs.docs.length, 2);
          expect(
            (await db
                    .collection('users')
                    .doc('u_t06')
                    .collection('wallets')
                    .doc('w_1')
                    .get())
                .data()!['balanceMinor'],
            1300000,
          );
        },
      );

      test(
        'T11, T12, T13, T16 & T18 — FCM foreground dedupe, background/terminated deep-link & logout token deactivation',
        () async {
          final db = FakeFirebaseFirestore();
          final driver = _TestFcmDriver()
            ..coldStartMessage = const IncomingBankingPushPayload(
              notificationId: 'notif_cold_1',
              transactionId: 'ver_tx_cold_99',
              walletId: 'w_vcb',
              connectionId: 'conn_1',
              direction: 'credit',
              verificationStatus: 'VERIFIED',
              title: '💰 Life OS — Tiền vừa về!',
              body: 'Giao dịch mới đã xác minh',
              openedFromSystemTray: true,
            );

          final fcmService = FcmBankingMessagingService(
            firestore: db,
            driver: driver,
          );
          final foregroundReceived = <IncomingBankingPushPayload>[];
          final deepLinksReceived = <IncomingBankingPushPayload>[];

          final subFg = fcmService.foregroundNotifications.listen(
            foregroundReceived.add,
          );
          final subDl = fcmService.deepLinkRequests.listen(
            deepLinksReceived.add,
          );

          await fcmService.bindAuthenticatedUser('user_a');
          await Future<void>.delayed(const Duration(milliseconds: 20));

          expect(
            fcmService.consumePendingColdStartDeepLink()?.transactionId,
            'ver_tx_cold_99',
          );
          expect(deepLinksReceived.length, 1);

          final devId = FcmBankingMessagingService.computeDeterministicDeviceId(
            'fcm_device_token_user_a',
          );
          final devSnap = await db
              .collection('users')
              .doc('user_a')
              .collection('devices')
              .doc(devId)
              .get();
          expect(devSnap.data()?['pushEnabled'], isTrue);

          const fgPush = IncomingBankingPushPayload(
            notificationId: 'notif_dup_77',
            transactionId: 'ver_tx_77',
            walletId: 'w_vcb',
            connectionId: 'conn_1',
            direction: 'credit',
            verificationStatus: 'VERIFIED',
            title: '💰 Life OS — Tiền vừa về!',
            body: '+500.000đ',
            openedFromSystemTray: false,
          );
          driver.foregroundCtrl.add(fgPush);
          driver.foregroundCtrl.add(fgPush);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(foregroundReceived.length, 1);

          driver.openedAppCtrl.add(fgPush);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(deepLinksReceived.length, 2);
          expect(deepLinksReceived.last.transactionId, 'ver_tx_77');

          await fcmService.unbindAndDeactivateOnLogout();
          expect(driver.unregisteredCalled, isTrue);
          final afterLogout = await db
              .collection('users')
              .doc('user_a')
              .collection('devices')
              .doc(devId)
              .get();
          expect(afterLogout.data()?['pushEnabled'], isFalse);

          driver.foregroundCtrl.add(
            const IncomingBankingPushPayload(
              notificationId: 'notif_after_logout',
              transactionId: 'ver_tx_leak',
              walletId: 'w_vcb',
              connectionId: 'conn_1',
              direction: 'credit',
              verificationStatus: 'VERIFIED',
              title: 'Should not leak',
              body: '',
              openedFromSystemTray: false,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(foregroundReceived.length, 1);

          await subFg.cancel();
          await subDl.cancel();
          await driver.dispose();
        },
      );

      test(
        'T22, T23, Legacy Token Migration, Test Notification Safety & Section 17 Explainable Rules',
        () async {
          final vcbCap = BankIntegrationCapability.forBankCode('VCB');
          final tpbCap = BankIntegrationCapability.forBankCode('TPB');
          expect(vcbCap.supportsWebhookCredit, isTrue);
          expect(vcbCap.supportsWebhookDebit, isFalse);
          expect(tpbCap.supportsWebhookDebit, isTrue);
          expect(
            tpbCap.requiredIntegrationType,
            BankIntegrationRequirement.tkpRequiredForDebit,
          );

          final db = FakeFirebaseFirestore();
          final auth = MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'u_mig'),
          );
          final notifDs = NotificationsRemoteDataSource(
            firestore: db,
            firebaseAuth: auth,
            bridge: AndroidNotificationBridge(),
            functionsInvokerOverride: (fn, payload) async => {
              'ok': true,
              'migrated': true,
            },
          );

          await expectLater(
            () => notifDs.linkVerifiedSePayConnection(
              userId: 'u_mig',
              bankCode: 'VCB',
              accountNumber: '1017588888',
              linkedWalletId: 'w_1',
              sepayApiToken: '',
            ),
            throwsA(isA<AppException>()),
          );

          await db
              .collection('users')
              .doc('u_mig')
              .collection('consents')
              .doc('sepay_api')
              .set({'apiToken': 'legacy_secret_sepay_token_123456'});
          final migrated = await notifDs.migrateLegacySePayConsentIfPresent(
            'u_mig',
          );
          expect(migrated, isTrue);
          expect(
            (await db
                    .collection('users')
                    .doc('u_mig')
                    .collection('consents')
                    .doc('sepay_api')
                    .get())
                .exists,
            isFalse,
          );

          final testNotif = await notifDs.sendTestBankingNotification('u_mig');
          expect(testNotif.isTestNotification, isTrue);
          expect(
            (await db
                    .collection('users')
                    .doc('u_mig')
                    .collection('transactions')
                    .get())
                .docs,
            isEmpty,
          );

          expect(
            ExplainableBankingRuleEngine.classify(
              content: 'GRAB CAR CHUYEN DI',
              direction: 'debit',
            ),
            'Di chuyển',
          );
          expect(
            ExplainableBankingRuleEngine.classify(
              content: 'SHOPEE VN DON HANG',
              direction: 'debit',
            ),
            'Mua sắm',
          );
          expect(
            ExplainableBankingRuleEngine.classify(
              content: 'THANH TOAN TIEN DIEN EVN',
              direction: 'debit',
            ),
            'Hóa đơn',
          );
          expect(
            ExplainableBankingRuleEngine.classify(
              content: 'PETROLIMEX DO XANG',
              direction: 'debit',
            ),
            'Xe cộ',
          );
          expect(
            ExplainableBankingRuleEngine.classify(
              content: 'LUONG THANG 11 CONG TY',
              direction: 'credit',
            ),
            'Thu nhập',
          );
          expect(
            ExplainableBankingRuleEngine.classify(
              content: 'GYM CALIFORNIA Q7',
              direction: 'debit',
              customRules: const [
                MerchantCategoryRuleEntity(
                  id: 'r1',
                  keyword: 'GYM CALIFORNIA',
                  categoryName: 'Sức khỏe',
                ),
              ],
            ),
            'Sức khỏe',
          );
          expect(
            ExplainableBankingRuleEngine.detectRecurringSuggestionLabel(
              'EVN TIEN DIEN T11',
              'debit',
            ),
            'Tiền điện hàng tháng',
          );
        },
      );
    },
  );
}
