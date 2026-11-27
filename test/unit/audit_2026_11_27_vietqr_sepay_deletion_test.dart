import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/security/bank_notification_parser.dart';
import 'package:life_os/core/services/android_notification_bridge.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/notifications/data/repositories/notifications_repository_impl.dart';
import 'package:life_os/features/notifications/domain/entities/notification_entities.dart';
import 'package:life_os/features/notifications/presentation/bloc/notification_ingestion_bloc.dart';
import 'package:life_os/features/notifications/presentation/pages/notifications_privacy_page.dart';

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

Future<void> _seedUserBankSetup({
  required FakeFirebaseFirestore db,
  required NotificationsRemoteDataSource remote,
  required String uid,
  int initialVcbBalance = 1000000,
  int initialTcbBalance = 500000,
}) async {
  await db.collection('users').doc(uid).set({
    'id': uid,
    'email': '$uid@lifeos.vn',
    'fullName': 'Nguyễn Minh',
    'onboardingCompleted': true,
  });

  await db
      .collection('users')
      .doc(uid)
      .collection('wallets')
      .doc('wallet_vcb')
      .set({
        'id': 'wallet_vcb',
        'ownerId': uid,
        'name': 'Vietcombank',
        'type': 'bank',
        'bankCode': 'VCB',
        'maskedAccount': '•••• 6868',
        'balanceMinor': initialVcbBalance,
        'isEstimatedBalance': true,
      });

  await db
      .collection('users')
      .doc(uid)
      .collection('wallets')
      .doc('wallet_tcb')
      .set({
        'id': 'wallet_tcb',
        'ownerId': uid,
        'name': 'Techcombank',
        'type': 'bank',
        'bankCode': 'TCB',
        'maskedAccount': '•••• 9999',
        'balanceMinor': initialTcbBalance,
        'isEstimatedBalance': true,
      });

  await db
      .collection('users')
      .doc(uid)
      .collection('wallets')
      .doc('wallet_cash_default')
      .set({
        'id': 'wallet_cash_default',
        'ownerId': uid,
        'name': 'Tiền mặt',
        'type': 'cash',
        'balanceMinor': 200000,
        'isEstimatedBalance': true,
      });

  await remote.saveLinkedBankAccount(
    userId: uid,
    walletId: 'wallet_vcb',
    bankBin: '970436',
    bankCode: 'VCB',
    bankName: 'Vietcombank',
    accountNumber: '0071000886868',
    accountHolderName: 'NGUYEN MINH',
    isDefault: true,
  );

  await remote.saveLinkedBankAccount(
    userId: uid,
    walletId: 'wallet_tcb',
    bankBin: '970407',
    bankCode: 'TCB',
    bankName: 'Techcombank',
    accountNumber: '190300009999',
    accountHolderName: 'NGUYEN MINH',
    isDefault: false,
  );

  await remote.updateConsent(
    userId: uid,
    enabled: true,
    allowedPackages: kSupportedVnBanks.map((b) => b.packageName).toList(),
    autoConfirmSignals: true,
    syncObservedBalance: false,
  );
}

void main() {
  setUp(() async {
    await UserBehaviorPrefs.resetForTest();
    NativeDeviceCalendarBridge.setDriverOverride(const _NoOpCalendarDriver());
  });

  tearDown(() async {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    await sl.reset();
  });

  group('CI Bank Catalog Compliance', () {
    test(
      'kSupportedVnBanks has >= 18 legitimate banking/e-wallet apps and ZERO SMS apps',
      () {
        expect(kSupportedVnBanks.length, greaterThanOrEqualTo(18));
        expect(
          kSupportedVnBanks.map((b) => b.packageName).toSet().length,
          kSupportedVnBanks.length,
        );
        for (final bank in kSupportedVnBanks) {
          expect(
            BankNotificationParser.isBlockedSmsOrMessagingPackage(
              bank.packageName,
            ),
            isFalse,
            reason: 'Blocked SMS/messaging package leaked: ${bank.packageName}',
          );
          expect(bank.bankCode.toUpperCase(), isNot('SMS'));
        }
      },
    );
  });

  group('H1: Transactional VietQR Verification, Partial Accumulation & NeedsReview', () {
    test(
      'PaymentOrderStatus labels & remainingAmountMinor helper are accurate',
      () {
        expect(PaymentOrderStatus.pending.statusLabelVi, 'Chờ chuyển khoản');
        expect(PaymentOrderStatus.partial.statusLabelVi, 'Đã nhận một phần');
        expect(PaymentOrderStatus.paid.statusLabelVi, 'Đã nhận đủ');
        expect(PaymentOrderStatus.needsReview.statusLabelVi, 'Cần đối soát');
        expect(PaymentOrderStatus.expired.statusLabelVi, 'Hết hạn');
        expect(PaymentOrderStatus.cancelled.statusLabelVi, 'Đã hủy');

        final order = PaymentOrderEntity(
          id: 'o1',
          ownerId: 'u1',
          walletId: 'w1',
          bankBin: '970436',
          bankCode: 'VCB',
          bankName: 'Vietcombank',
          accountNumber: '0071000886868',
          accountHolderName: 'NGUYEN MINH',
          amountMinor: 300000,
          receivedAmountMinor: 100000,
          paymentCode: 'LOABC123',
          description: 'Thu tien',
          emvQrPayload: '000201',
          status: PaymentOrderStatus.partial,
          createdAt: DateTime(2026, 11, 27),
        );
        expect(order.remainingAmountMinor, 200000);
        expect(order.currency, 'VND');
        expect(order.isPaid, isFalse);
      },
    );

    test(
      'Exact VietQR payment matching bank + accountTail + amount marks order paid and credits order wallet',
      () async {
        final db = FakeFirebaseFirestore();
        final remote = NotificationsRemoteDataSource(
          firestore: db,
          firebaseAuth: MockFirebaseAuth(),
          bridge: AndroidNotificationBridge(),
        );
        const uid = 'u_h1_exact';
        await _seedUserBankSetup(db: db, remote: remote, uid: uid);

        final order = await remote.createPaymentOrder(
          userId: uid,
          walletId: 'wallet_vcb',
          bankBin: '970436',
          bankCode: 'VCB',
          bankName: 'Vietcombank',
          accountNumber: '0071000886868',
          accountHolderName: 'NGUYEN MINH',
          amountMinor: 300000,
          description: 'Tiền ăn trưa',
        );

        final outcome = await remote.ingestAndroidNotification(
          userId: uid,
          defaultWalletId: 'wallet_cash_default',
          packageName: 'com.VCB',
          title: 'VCB Digibank',
          body:
              'TK 0071***6868 GD: +300.000VND. ND: Chuyen khoan ${order.paymentCode}',
          notificationId: 'notif_exact_1',
        );

        expect(outcome.kind, IngestionOutcomeKind.autoReconciledOrder);
        final orders = await remote.watchPaymentOrders(uid).first;
        final updated = orders.single;
        expect(updated.status, PaymentOrderStatus.paid);
        expect(updated.status.statusLabelVi, 'Đã nhận đủ');
        expect(updated.isPaid, isTrue);
        expect(updated.receivedAmountMinor, 300000);
        expect(updated.remainingAmountMinor, 0);
        expect(updated.paidAt, isNotNull);
        expect(updated.matchedTransactionIds.length, 1);

        final walletSnap = await db
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_vcb')
            .get();
        expect(walletSnap.data()?['balanceMinor'], 1300000);
      },
    );

    test(
      'Underpaid VietQR transitions to partial, accumulates second partial to paid, and prevents duplicate/concurrent double count',
      () async {
        final db = FakeFirebaseFirestore();
        final remote = NotificationsRemoteDataSource(
          firestore: db,
          firebaseAuth: MockFirebaseAuth(),
          bridge: AndroidNotificationBridge(),
        );
        const uid = 'u_h1_partial';
        await _seedUserBankSetup(db: db, remote: remote, uid: uid);

        final order = await remote.createPaymentOrder(
          userId: uid,
          walletId: 'wallet_vcb',
          bankBin: '970436',
          bankCode: 'VCB',
          bankName: 'Vietcombank',
          accountNumber: '0071000886868',
          accountHolderName: 'NGUYEN MINH',
          amountMinor: 300000,
          description: 'Tiền quỹ nhóm',
        );

        // Concurrent replay of identical 100k notification (same notificationId/sourceEventKey)
        final replayResults = await Future.wait([
          remote.ingestAndroidNotification(
            userId: uid,
            defaultWalletId: 'wallet_cash_default',
            packageName: 'com.VCB',
            title: 'VCB Digibank',
            body:
                'TK 0071***6868 GD: +100.000VND. ND: Dot 1 ${order.paymentCode}',
            notificationId: 'notif_part_1',
          ),
          remote.ingestAndroidNotification(
            userId: uid,
            defaultWalletId: 'wallet_cash_default',
            packageName: 'com.VCB',
            title: 'VCB Digibank',
            body:
                'TK 0071***6868 GD: +100.000VND. ND: Dot 1 ${order.paymentCode}',
            notificationId: 'notif_part_1',
          ),
        ]);

        expect(
          replayResults
              .where((r) => r.kind == IngestionOutcomeKind.autoReconciledOrder)
              .length,
          1,
        );
        expect(
          replayResults
              .where((r) => r.kind == IngestionOutcomeKind.duplicateIgnored)
              .length,
          1,
        );

        var orders = await remote.watchPaymentOrders(uid).first;
        var current = orders.single;
        expect(current.status, PaymentOrderStatus.partial);
        expect(current.isPaid, isFalse);
        expect(current.paidAt, isNull);
        expect(current.receivedAmountMinor, 100000);
        expect(current.remainingAmountMinor, 200000);
        expect(current.receivedContributions.length, 1);

        // Sequential replay of same sourceEventKey also ignored
        final dupAgain = await remote.ingestAndroidNotification(
          userId: uid,
          defaultWalletId: 'wallet_cash_default',
          packageName: 'com.VCB',
          title: 'VCB Digibank',
          body:
              'TK 0071***6868 GD: +100.000VND. ND: Dot 1 ${order.paymentCode}',
          notificationId: 'notif_part_1',
        );
        expect(dupAgain.kind, IngestionOutcomeKind.duplicateIgnored);

        // Second partial payment of 200k with distinct notificationId transitions partial -> paid
        final secondOutcome = await remote.ingestAndroidNotification(
          userId: uid,
          defaultWalletId: 'wallet_cash_default',
          packageName: 'com.VCB',
          title: 'VCB Digibank',
          body:
              'TK 0071***6868 GD: +200.000VND. ND: Dot 2 ${order.paymentCode}',
          notificationId: 'notif_part_2',
        );
        expect(secondOutcome.kind, IngestionOutcomeKind.autoReconciledOrder);

        orders = await remote.watchPaymentOrders(uid).first;
        current = orders.single;
        expect(current.status, PaymentOrderStatus.paid);
        expect(current.isPaid, isTrue);
        expect(current.paidAt, isNotNull);
        expect(current.receivedAmountMinor, 300000);
        expect(current.remainingAmountMinor, 0);
        expect(current.receivedContributions.length, 2);
        expect(current.matchedTransactionIds.length, 2);

        final walletSnap = await db
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_vcb')
            .get();
        expect(walletSnap.data()?['balanceMinor'], 1300000);
      },
    );

    test(
      'Overpayment (350k on 300k order) sets needsReview with reviewReason and NEVER marks paid',
      () async {
        final db = FakeFirebaseFirestore();
        final remote = NotificationsRemoteDataSource(
          firestore: db,
          firebaseAuth: MockFirebaseAuth(),
          bridge: AndroidNotificationBridge(),
        );
        const uid = 'u_h1_overpay';
        await _seedUserBankSetup(db: db, remote: remote, uid: uid);

        final order = await remote.createPaymentOrder(
          userId: uid,
          walletId: 'wallet_vcb',
          bankBin: '970436',
          bankCode: 'VCB',
          bankName: 'Vietcombank',
          accountNumber: '0071000886868',
          accountHolderName: 'NGUYEN MINH',
          amountMinor: 300000,
          description: 'Đơn thu 300k',
        );

        final outcome = await remote.ingestAndroidNotification(
          userId: uid,
          defaultWalletId: 'wallet_cash_default',
          packageName: 'com.VCB',
          title: 'VCB Digibank',
          body:
              'TK 0071***6868 GD: +350.000VND. ND: Gui du ${order.paymentCode}',
          notificationId: 'notif_overpay_1',
        );

        expect(outcome.kind, IngestionOutcomeKind.createdProvisional);
        final updated = (await remote.watchPaymentOrders(uid).first).single;
        expect(updated.status, PaymentOrderStatus.needsReview);
        expect(updated.isPaid, isFalse);
        expect(updated.paidAt, isNull);
        expect(updated.receivedAmountMinor, 350000);
        expect(
          updated.reviewReason,
          contains('Thực nhận vượt số tiền yêu cầu'),
        );
      },
    );

    test(
      'Wrong bank (TCB) or wrong accountTail on VCB order sets needsReview and does NOT credit order wallet',
      () async {
        final db = FakeFirebaseFirestore();
        final remote = NotificationsRemoteDataSource(
          firestore: db,
          firebaseAuth: MockFirebaseAuth(),
          bridge: AndroidNotificationBridge(),
        );
        const uid = 'u_h1_mismatch';
        await _seedUserBankSetup(db: db, remote: remote, uid: uid);

        final vcbOrder = await remote.createPaymentOrder(
          userId: uid,
          walletId: 'wallet_vcb',
          bankBin: '970436',
          bankCode: 'VCB',
          bankName: 'Vietcombank',
          accountNumber: '0071000886868',
          accountHolderName: 'NGUYEN MINH',
          amountMinor: 300000,
          description: 'Thu vào VCB',
        );

        // 1. Incoming TCB notification carrying VCB's paymentCode
        final wrongBankOutcome = await remote.ingestAndroidNotification(
          userId: uid,
          defaultWalletId: 'wallet_cash_default',
          packageName: 'com.techcombank.bb.app',
          title: 'Techcombank',
          body: 'TK 1903***9999 +300.000 VND. ND: ${vcbOrder.paymentCode}',
          notificationId: 'notif_wrong_bank_1',
        );
        expect(wrongBankOutcome.kind, IngestionOutcomeKind.createdProvisional);

        final updatedOrder =
            (await remote.watchPaymentOrders(uid).first).single;
        expect(updatedOrder.status, PaymentOrderStatus.needsReview);
        expect(updatedOrder.isPaid, isFalse);
        expect(updatedOrder.receivedAmountMinor, 0);
        expect(
          updatedOrder.reviewReason,
          'Sai ngân hàng hoặc tài khoản nhận tiền so với đơn VietQR.',
        );

        // VCB wallet balance MUST NOT be credited by TCB mismatch!
        final vcbWalletSnap = await db
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_vcb')
            .get();
        expect(vcbWalletSnap.data()?['balanceMinor'], 1000000);

        final txSnap = await db
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .doc(wrongBankOutcome.transactionId!)
            .get();
        expect(txSnap.data()?['walletId'], isNot('wallet_vcb'));
        expect(txSnap.data()?['verification'], 'needsReview');
        expect(txSnap.data()?['ledgerApplied'], isFalse);

        // 2. Wrong accountTail within same bank (VCB ***1111 vs order ***6868)
        final vcbOrder2 = await remote.createPaymentOrder(
          userId: uid,
          walletId: 'wallet_vcb',
          bankBin: '970436',
          bankCode: 'VCB',
          bankName: 'Vietcombank',
          accountNumber: '0071000886868',
          accountHolderName: 'NGUYEN MINH',
          amountMinor: 250000,
          description: 'Thu vào VCB 6868',
        );

        await remote.ingestAndroidNotification(
          userId: uid,
          defaultWalletId: 'wallet_cash_default',
          packageName: 'com.VCB',
          title: 'VCB Digibank',
          body: 'TK 0071***1111 GD: +250.000VND. ND: ${vcbOrder2.paymentCode}',
          notificationId: 'notif_wrong_tail_2',
        );

        final orders = await remote.watchPaymentOrders(uid).first;
        final checkedOrder2 = orders.firstWhere((o) => o.id == vcbOrder2.id);
        expect(checkedOrder2.status, PaymentOrderStatus.needsReview);
        expect(checkedOrder2.isPaid, isFalse);
        expect(checkedOrder2.receivedAmountMinor, 0);
      },
    );
  });

  group('H2: SePay Disconnect PendingRevocation State & Retry UI', () {
    test(
      'When disconnectBankConnection Cloud Function fails, throws SERVER_REVOCATION_PENDING and writes pendingRevocation (NOT disconnected/revoked)',
      () async {
        final db = FakeFirebaseFirestore();
        const uid = 'u_h2_fail';
        const connId = 'conn_vcb_1';
        await db
            .collection('users')
            .doc(uid)
            .collection('bank_connections')
            .doc(connId)
            .set({
              'id': connId,
              'ownerId': uid,
              'provider': 'sepay',
              'bankCode': 'VCB',
              'bankName': 'Vietcombank',
              'accountMasked': '•••• 6868',
              'linkedWalletId': 'wallet_vcb',
              'status': 'connected',
              'consentStatus': 'granted',
            });

        final remoteFailing = NotificationsRemoteDataSource(
          firestore: db,
          firebaseAuth: MockFirebaseAuth(),
          bridge: AndroidNotificationBridge(),
          functionsInvokerOverride: (fnName, payload) async {
            throw Exception('network-timeout');
          },
        );

        await expectLater(
          remoteFailing.disconnectBankConnection(
            userId: uid,
            connectionId: connId,
          ),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              'SERVER_REVOCATION_PENDING',
            ),
          ),
        );

        final connDoc = await db
            .collection('users')
            .doc(uid)
            .collection('bank_connections')
            .doc(connId)
            .get();
        expect(connDoc.data()?['status'], 'pendingRevocation');
        expect(connDoc.data()?['consentStatus'], 'revocation_pending');
        expect(connDoc.data()?['revocationRequestedAt'], isA<Timestamp>());
        expect(
          connDoc.data()?['lastRevocationError'].toString(),
          contains('network-timeout'),
        );

        final mappedList = await remoteFailing.watchBankConnections(uid).first;
        expect(
          mappedList.single.status,
          BankConnectionStatus.pendingRevocation,
        );
        expect(mappedList.single.isVerifiedConnected, isFalse);

        // Verify NotificationIngestionBloc surfaces failure and NEVER claims disconnected success
        final bloc = NotificationIngestionBloc(
          repository: NotificationsRepositoryImpl(remoteFailing),
        );
        bloc.add(
          const BankConnectionDisconnected(userId: uid, connectionId: connId),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(bloc.state.failure?.code, 'SERVER_REVOCATION_PENDING');
        expect(bloc.state.infoMessage, isNull);
        await bloc.close();
      },
    );

    test(
      'When disconnectBankConnection Cloud Function succeeds, completes cleanly and marks disconnected/revoked',
      () async {
        final db = FakeFirebaseFirestore();
        const uid = 'u_h2_ok';
        const connId = 'conn_vcb_ok';
        await db
            .collection('users')
            .doc(uid)
            .collection('bank_connections')
            .doc(connId)
            .set({
              'id': connId,
              'ownerId': uid,
              'provider': 'sepay',
              'bankCode': 'VCB',
              'bankName': 'Vietcombank',
              'accountMasked': '•••• 6868',
              'linkedWalletId': 'wallet_vcb',
              'status': 'connected',
              'consentStatus': 'granted',
            });

        final remoteOk = NotificationsRemoteDataSource(
          firestore: db,
          firebaseAuth: MockFirebaseAuth(),
          bridge: AndroidNotificationBridge(),
          functionsInvokerOverride: (fnName, payload) async =>
              <String, dynamic>{'ok': true},
        );

        await remoteOk.disconnectBankConnection(
          userId: uid,
          connectionId: connId,
        );

        final connDoc = await db
            .collection('users')
            .doc(uid)
            .collection('bank_connections')
            .doc(connId)
            .get();
        expect(connDoc.data()?['status'], 'disconnected');
        expect(connDoc.data()?['consentStatus'], 'revoked');
      },
    );

    testWidgets(
      'NotificationsPrivacyPage renders partial VietQR breakdown, needsReview reason, and Thử ngắt lại button for pendingRevocation at 360x800 @ 1.25x',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final db = FakeFirebaseFirestore();
        const uid = 'u_h1_h2_ui';
        await db.collection('users').doc(uid).set({
          'id': uid,
          'email': 'ui@lifeos.vn',
          'fullName': 'Ngọc Anh',
          'onboardingCompleted': true,
        });
        await db
            .collection('users')
            .doc(uid)
            .collection('bank_connections')
            .doc('conn_retry_1')
            .set({
              'id': 'conn_retry_1',
              'ownerId': uid,
              'provider': 'sepay',
              'bankCode': 'VCB',
              'bankName': 'Vietcombank',
              'accountMasked': '•••• 6868',
              'linkedWalletId': 'wallet_vcb',
              'status': 'pending_revocation',
              'consentStatus': 'revocation_pending',
            });
        await db
            .collection('users')
            .doc(uid)
            .collection('payment_orders')
            .doc('ord_partial_ui')
            .set({
              'id': 'ord_partial_ui',
              'ownerId': uid,
              'walletId': 'wallet_vcb',
              'bankBin': '970436',
              'bankCode': 'VCB',
              'bankName': 'Vietcombank',
              'accountNumber': '0071000886868',
              'accountHolderName': 'NGOC ANH',
              'amountMinor': 300000,
              'receivedAmountMinor': 100000,
              'currency': 'VND',
              'paymentCode': 'LOPART01',
              'description': 'Đặt cọc nhóm',
              'emvQrPayload': '000201',
              'status': 'partial',
              'createdAt': Timestamp.fromDate(DateTime(2026, 11, 27, 10, 0)),
            });
        await db
            .collection('users')
            .doc(uid)
            .collection('payment_orders')
            .doc('ord_review_ui')
            .set({
              'id': 'ord_review_ui',
              'ownerId': uid,
              'walletId': 'wallet_vcb',
              'bankBin': '970436',
              'bankCode': 'VCB',
              'bankName': 'Vietcombank',
              'accountNumber': '0071000886868',
              'accountHolderName': 'NGOC ANH',
              'amountMinor': 200000,
              'receivedAmountMinor': 250000,
              'currency': 'VND',
              'paymentCode': 'LOREVW02',
              'description': 'Vé xem phim',
              'emvQrPayload': '000201',
              'status': 'needsReview',
              'reviewReason': 'Thực nhận vượt số tiền yêu cầu (dư 50.000 ₫).',
              'createdAt': Timestamp.fromDate(DateTime(2026, 11, 27, 9, 0)),
            });

        var disconnectCalled = 0;
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'ui@lifeos.vn',
            displayName: 'Ngọc Anh',
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
          functionsInvokerOverride: (fnName, payload) async {
            if (fnName == 'disconnectBankConnection') {
              disconnectCalled += 1;
              return <String, dynamic>{'ok': true};
            }
            return <String, dynamic>{'ok': true};
          },
        );

        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.25),
            ),
            child: LifeOsApp(),
          ),
        );
        await tester.pumpAndSettle();

        final navCtx = tester.element(find.byType(Scaffold).first);
        GoRouter.of(navCtx).push('/notifications-privacy');
        await tester.pumpAndSettle();
        expect(find.byType(NotificationsPrivacyPage), findsOneWidget);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();

        final pageScrollable = find.descendant(
          of: find.byType(NotificationsPrivacyPage),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text('Đã nhận một phần'),
          200,
          scrollable: pageScrollable.first,
        );
        await tester.pumpAndSettle();

        expect(find.text('Đã nhận một phần'), findsOneWidget);
        expect(
          find.text('Đã nhận 100.000 ₫ / 300.000 ₫ (còn thiếu 200.000 ₫)'),
          findsOneWidget,
        );
        expect(find.text('Cần đối soát'), findsOneWidget);
        expect(
          find.textContaining('Thực nhận vượt số tiền yêu cầu (dư 50.000 ₫).'),
          findsOneWidget,
        );

        // Scroll to Bank Connections card and verify pendingRevocation retry button
        final retryBtn = find.byKey(const Key('retry_disconnect_conn_retry_1'));
        await tester.scrollUntilVisible(
          retryBtn,
          300,
          scrollable: pageScrollable.first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Đang chờ thu hồi trên máy chủ'), findsOneWidget);
        expect(find.text('Thử ngắt lại'), findsOneWidget);

        await tester.tap(retryBtn);
        await tester.pumpAndSettle();
        expect(disconnectCalled, 1);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  });

  group('H5: Account Deletion Server-First Ordering & Legacy/Nested Cleanup', () {
    test(
      'Aborts BEFORE wiping wallets/transactions/vault when server deleteUserAccountData fails',
      () async {
        final db = FakeFirebaseFirestore();
        const uid = 'u_h5_abort';
        final callOrder = <String>[];
        var vaultCleared = false;

        await db.collection('users').doc(uid).set({'id': uid});
        await db
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w1')
            .set({'id': 'w1', 'balanceMinor': 900000});
        await db
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .doc('t1')
            .set({'id': 't1', 'amountMinor': 50000});

        final remote = NotificationsRemoteDataSource(
          firestore: db,
          firebaseAuth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: uid, email: 'abort@lifeos.vn'),
          ),
          bridge: AndroidNotificationBridge(),
          functionsInvokerOverride: (fnName, payload) async {
            callOrder.add('fn:$fnName');
            throw Exception('server-unavailable');
          },
          clearUserVaultOverride: (clearedUid) async {
            vaultCleared = true;
            callOrder.add('vault:$clearedUid');
          },
        );

        await expectLater(
          remote.deleteAccountAndPersonalData(uid),
          throwsException,
        );

        // Tried server function twice and aborted WITHOUT wiping client data or vault!
        expect(
          callOrder,
          equals(['fn:deleteUserAccountData', 'fn:deleteUserAccountData']),
        );
        expect(vaultCleared, isFalse);
        expect((await db.collection('users').doc(uid).get()).exists, isTrue);
        expect(
          (await db.collection('users').doc(uid).collection('wallets').get())
              .docs
              .length,
          1,
        );
        expect(
          (await db
                  .collection('users')
                  .doc(uid)
                  .collection('transactions')
                  .get())
              .docs
              .length,
          1,
        );
      },
    );

    test(
      'Invokes deleteUserAccountData BEFORE wiping data, purges legacy medications/health_logs/medical_profiles, daily_preferences, personal_funds/*/fund_audits, and calls user-scoped vault clear',
      () async {
        final db = FakeFirebaseFirestore();
        const uid = 'u_h5_full';
        final events = <String>[];
        var walletsExistedDuringServerCall = false;

        final uRef = db.collection('users').doc(uid);
        await uRef.set({'id': uid, 'email': 'full@lifeos.vn'});
        await uRef.collection('wallets').doc('w1').set({'balanceMinor': 1000});
        await uRef.collection('transactions').doc('t1').set({
          'amountMinor': 50,
        });
        await uRef.collection('daily_preferences').doc('dp1').set({'ok': true});
        await uRef.collection('medications').doc('med1').set({'name': 'A'});
        await uRef.collection('health_logs').doc('hl1').set({'bpm': 72});
        await uRef.collection('medical_profiles').doc('mp1').set({
          'blood': 'O',
        });

        final fundRef = uRef.collection('personal_funds').doc('pf1');
        await fundRef.set({'name': 'Quỹ dự phòng'});
        await fundRef.collection('contributions').doc('c1').set({'amt': 100});
        await fundRef.collection('expenses').doc('e1').set({'amt': 50});
        await fundRef.collection('fund_audits').doc('fa1').set({'delta': 100});

        final remote = NotificationsRemoteDataSource(
          firestore: db,
          firebaseAuth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: uid, email: 'full@lifeos.vn'),
          ),
          bridge: AndroidNotificationBridge(),
          functionsInvokerOverride: (fnName, payload) async {
            events.add('server:$fnName');
            final wSnap = await uRef.collection('wallets').get();
            walletsExistedDuringServerCall = wSnap.docs.isNotEmpty;
            return <String, dynamic>{'ok': true};
          },
          clearUserVaultOverride: (clearedUid) async {
            events.add('vault:$clearedUid');
          },
        );

        await remote.deleteAccountAndPersonalData(uid);

        expect(walletsExistedDuringServerCall, isTrue);
        expect(events, equals(['server:deleteUserAccountData', 'vault:$uid']));
        expect((await uRef.get()).exists, isFalse);
        expect((await uRef.collection('wallets').get()).docs, isEmpty);
        expect((await uRef.collection('transactions').get()).docs, isEmpty);
        expect(
          (await uRef.collection('daily_preferences').get()).docs,
          isEmpty,
        );
        expect((await uRef.collection('medications').get()).docs, isEmpty);
        expect((await uRef.collection('health_logs').get()).docs, isEmpty);
        expect((await uRef.collection('medical_profiles').get()).docs, isEmpty);
        expect((await uRef.collection('personal_funds').get()).docs, isEmpty);
        expect((await fundRef.collection('contributions').get()).docs, isEmpty);
        expect((await fundRef.collection('expenses').get()).docs, isEmpty);
        expect((await fundRef.collection('fund_audits').get()).docs, isEmpty);
      },
    );
  });

  group('M7: FinancePage Truthful Bank Verification Badge', () {
    testWidgets(
      'Manual/CSV/Android-notification entries NEVER show "Ngân hàng xác thực"; only bankApi/bankWebhook + verified shows it',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final db = FakeFirebaseFirestore();
        const uid = 'u_m7_truth';
        final now = DateTime.now();
        final monthKey =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

        await db.collection('users').doc(uid).set({
          'id': uid,
          'email': 'm7@lifeos.vn',
          'fullName': 'Minh Đức',
          'onboardingCompleted': true,
        });
        await db
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_vcb')
            .set({
              'id': 'wallet_vcb',
              'ownerId': uid,
              'name': 'Vietcombank',
              'type': 'bank',
              'balanceMinor': 5000000,
              'isEstimatedBalance': false,
            });

        // Tampered/legacy manual entry claiming `verified`
        await db
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .doc('tx_manual_fake_ver')
            .set({
              'id': 'tx_manual_fake_ver',
              'ownerId': uid,
              'walletId': 'wallet_vcb',
              'categoryName': 'Ăn uống',
              'kind': 'expense',
              'direction': 'debit',
              'amountMinor': 65000,
              'merchant': 'Phở Bò Thủ Công',
              'occurredAt': Timestamp.fromDate(now),
              'monthKey': monthKey,
              'sourceKind': 'manual',
              'verification': 'verified',
              'crossSourceFingerprint': 'fp_m7_1',
            });

        // Android notification entry claiming `verified`
        await db
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .doc('tx_android_fake_ver')
            .set({
              'id': 'tx_android_fake_ver',
              'ownerId': uid,
              'walletId': 'wallet_vcb',
              'categoryName': 'Mua sắm',
              'kind': 'expense',
              'direction': 'debit',
              'amountMinor': 120000,
              'merchant': 'Thông báo Thiết Bị',
              'occurredAt': Timestamp.fromDate(
                now.subtract(const Duration(minutes: 2)),
              ),
              'monthKey': monthKey,
              'sourceKind': 'androidNotification',
              'verification': 'verified',
              'crossSourceFingerprint': 'fp_m7_2',
            });

        // Genuine server bankApi verified entry
        await db
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .doc('tx_bank_api_ver')
            .set({
              'id': 'tx_bank_api_ver',
              'ownerId': uid,
              'walletId': 'wallet_vcb',
              'categoryName': 'Lương & Thu nhập',
              'kind': 'income',
              'direction': 'credit',
              'amountMinor': 15000000,
              'merchant': 'Chuyển khoản SePay API',
              'occurredAt': Timestamp.fromDate(
                now.subtract(const Duration(minutes: 5)),
              ),
              'monthKey': monthKey,
              'sourceKind': 'bankApi',
              'verification': 'verified',
              'crossSourceFingerprint': 'fp_m7_3',
            });

        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'm7@lifeos.vn',
            displayName: 'Minh Đức',
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
              textScaler: TextScaler.linear(1.25),
            ),
            child: LifeOsApp(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Tài chính').last);
        await tester.pumpAndSettle();

        final txListScrollable = find
            .descendant(
              of: find.byKey(const Key('transactions_list_view')),
              matching: find.byType(Scrollable),
            )
            .first;

        // 1. Manual transaction receipt MUST NOT show "Ngân hàng xác thực"
        final manualTile = find.text('Phở Bò Thủ Công');
        await tester.scrollUntilVisible(
          manualTile,
          300,
          scrollable: txListScrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(manualTile);
        await tester.pumpAndSettle();
        expect(find.text('Ngân hàng xác thực'), findsNothing);
        expect(find.text('Đã ghi sổ cái'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();

        // 2. Android notification transaction receipt MUST NOT show "Ngân hàng xác thực"
        final androidTile = find.text('Thông báo Thiết Bị');
        await tester.scrollUntilVisible(
          androidTile,
          300,
          scrollable: txListScrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(androidTile);
        await tester.pumpAndSettle();
        expect(find.text('Ngân hàng xác thực'), findsNothing);
        expect(find.text('Đã ghi nhận (Thông báo)'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();

        // 3. Genuine bankApi verified transaction DOES show "Ngân hàng xác thực"
        final bankApiTile = find.text('Chuyển khoản SePay API');
        await tester.scrollUntilVisible(
          bankApiTile,
          300,
          scrollable: txListScrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(bankApiTile);
        await tester.pumpAndSettle();
        expect(find.text('Ngân hàng xác thực'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  });
}
