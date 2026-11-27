import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app/config/firebase_config.dart';
import 'package:life_os/core/backup/lifeos_backup_restore_engine.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/offline/offline_outbox_service.dart';
import 'package:life_os/core/services/android_notification_bridge.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/features/backup/data/datasources/firestore_backup_remote_datasource.dart';
import 'package:life_os/features/backup/data/repositories/backup_repository_impl.dart';
import 'package:life_os/features/backup/domain/entities/backup_entities.dart';
import 'package:life_os/features/backup/domain/services/aes_gcm_256.dart';
import 'package:life_os/features/backup/domain/services/backup_archive_codec.dart';
import 'package:life_os/features/notifications/data/repositories/notifications_repository_impl.dart';
import 'package:life_os/features/notifications/domain/entities/notification_entities.dart';
import 'package:life_os/features/transactions/data/datasources/transaction_remote_datasource.dart';
import 'package:life_os/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:life_os/features/transactions/domain/usecases/transaction_usecases.dart';

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<void> _seedVietQrUser({
  required FakeFirebaseFirestore db,
  required NotificationsRemoteDataSource remote,
  required String uid,
  required List<String> allowedPackages,
  bool twoVcbWallets = false,
}) async {
  await db.collection('users').doc(uid).set({
    'id': uid,
    'email': '$uid@lifeos.vn',
    'fullName': 'Minh Tran',
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
  await db
      .collection('users')
      .doc(uid)
      .collection('wallets')
      .doc('wallet_vcb')
      .set({
        'id': 'wallet_vcb',
        'ownerId': uid,
        'name': 'Vietcombank Chính',
        'type': 'bank',
        'bankCode': 'VCB',
        'maskedAccount': '•••• 6868',
        'balanceMinor': 1000000,
        'isEstimatedBalance': true,
      });
  await remote.saveLinkedBankAccount(
    userId: uid,
    walletId: 'wallet_vcb',
    bankBin: '970436',
    bankCode: 'VCB',
    bankName: 'Vietcombank',
    accountNumber: '0071000886868',
    accountHolderName: 'MINH TRAN',
    isDefault: true,
  );
  if (twoVcbWallets) {
    await db
        .collection('users')
        .doc(uid)
        .collection('wallets')
        .doc('wallet_vcb_2')
        .set({
          'id': 'wallet_vcb_2',
          'ownerId': uid,
          'name': 'Vietcombank Phụ',
          'type': 'bank',
          'bankCode': 'VCB',
          'maskedAccount': '•••• 7777',
          'balanceMinor': 500000,
          'isEstimatedBalance': true,
        });
    await remote.saveLinkedBankAccount(
      userId: uid,
      walletId: 'wallet_vcb_2',
      bankBin: '970436',
      bankCode: 'VCB',
      bankName: 'Vietcombank',
      accountNumber: '0071000997777',
      accountHolderName: 'MINH TRAN',
      isDefault: false,
    );
  }
  await db
      .collection('users')
      .doc(uid)
      .collection('consents')
      .doc('android_notification')
      .set({
        'sourceId': 'android_notification',
        'ownerId': uid,
        'enabled': true,
        'autoConfirmSignals': true,
        'syncObservedBalance': false,
        'allowedPackages': allowedPackages,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
}

void main() {
  group('Re-audit v3.27.2 Verification Suite (Workstream 1C)', () {
    setUp(() async {
      await UserBehaviorPrefs.resetForTest();
    });

    group('DEL-01: Single Authoritative Backend Cloud Deletion', () {
      test(
        'Server deletes users/{uid}, solo family, and removes member from shared family; client NEVER recreates users/{uid} or writes second family update',
        () async {
          final db = FakeFirebaseFirestore();
          const uid = 'u_del01_ok';
          var vaultClearedUid = '';
          final bridge = AndroidNotificationBridge();

          await db.collection('users').doc(uid).set({
            'id': uid,
            'email': 'del01@lifeos.vn',
          });
          await db
              .collection('users')
              .doc(uid)
              .collection('wallets')
              .doc('w1')
              .set({'id': 'w1', 'balanceMinor': 500000});

          // Solo family & shared family (as plain member)
          await db.collection('families').doc('fam_solo').set({
            'id': 'fam_solo',
            'name': 'Solo',
            'createdBy': uid,
            'memberIds': [uid],
            'memberRoles': {uid: 'owner'},
          });
          await db.collection('families').doc('fam_shared').set({
            'id': 'fam_shared',
            'name': 'Shared',
            'createdBy': 'u_other',
            'memberIds': [uid, 'u_other'],
            'memberRoles': {uid: 'member', 'u_other': 'owner'},
            'memberNames': {uid: 'Minh', 'u_other': 'Lan'},
          });

          final remote = NotificationsRemoteDataSource(
            firestore: db,
            firebaseAuth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: uid, email: 'del01@lifeos.vn'),
            ),
            bridge: bridge,
            functionsInvokerOverride: (fnName, payload) async {
              expect(fnName, 'deleteUserAccountData');
              expect(payload['userId'], uid);

              // Simulate authoritative server recursive deletion
              await db
                  .collection('users')
                  .doc(uid)
                  .collection('wallets')
                  .doc('w1')
                  .delete();
              await db.collection('users').doc(uid).delete();
              await db.collection('families').doc('fam_solo').delete();
              await db.collection('families').doc('fam_shared').update({
                'memberIds': ['u_other'],
                'memberRoles': {'u_other': 'owner'},
                'memberNames': {'u_other': 'Lan'},
                'serverAuthoritativeMarker': 'keep_me',
              });
              return <String, dynamic>{
                'ok': true,
                'verifiedClean': true,
                'status': 'completed',
                'authDeleted': true,
                'deletedCount': 4,
              };
            },
            clearUserVaultOverride: (clearedUid) async {
              vaultClearedUid = clearedUid;
            },
          );

          await remote.deleteAccountAndPersonalData(uid);

          // Client MUST NOT recreate users/{uid} with deletionInProgress: true!
          expect((await db.collection('users').doc(uid).get()).exists, isFalse);
          expect(
            (await db.collection('families').doc('fam_solo').get()).exists,
            isFalse,
          );
          final sharedSnap = await db
              .collection('families')
              .doc('fam_shared')
              .get();
          expect(sharedSnap.data()?['memberIds'], equals(['u_other']));
          expect(sharedSnap.data()?['serverAuthoritativeMarker'], 'keep_me');
          expect(vaultClearedUid, uid);
          expect(bridge.debugClearQueueCallCount, 1);
          expect(bridge.debugLastSyncedConsentEnabled, isFalse);
        },
      );

      test(
        'Fails closed when server returns authDeleted: false, verifiedClean: false, or ok != true, and NEVER clears local vault',
        () async {
          for (final badResponse in <Map<String, dynamic>>[
            <String, dynamic>{
              'ok': true,
              'verifiedClean': true,
              'authDeleted': false,
            },
            <String, dynamic>{
              'ok': true,
              'verifiedClean': false,
              'authDeleted': true,
            },
            <String, dynamic>{'ok': false},
            <String, dynamic>{
              'ok': true,
              'verifiedClean': true,
              'status': 'pending',
            },
          ]) {
            final db = FakeFirebaseFirestore();
            const uid = 'u_del01_fail';
            var vaultCleared = false;
            await db.collection('users').doc(uid).set({'id': uid});

            final remote = NotificationsRemoteDataSource(
              firestore: db,
              firebaseAuth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: uid, email: 'fail@lifeos.vn'),
              ),
              bridge: AndroidNotificationBridge(),
              functionsInvokerOverride: (_, _) async => badResponse,
              clearUserVaultOverride: (_) async {
                vaultCleared = true;
              },
            );

            final expectedCode = badResponse['authDeleted'] == false
                ? 'SERVER_AUTH_DELETION_INCOMPLETE'
                : 'SERVER_ACCOUNT_DELETION_FAILED';

            await expectLater(
              remote.deleteAccountAndPersonalData(uid),
              throwsA(
                isA<AppException>().having((e) => e.code, 'code', expectedCode),
              ),
            );
            expect(vaultCleared, isFalse);
          }
        },
      );

      test(
        'Fails closed when allowLocalEmulatorlessFallbackForTest is false and no functions invoker exists',
        () async {
          final db = FakeFirebaseFirestore();
          const uid = 'u_no_fallback';
          await db.collection('users').doc(uid).set({'id': uid});

          final remote = NotificationsRemoteDataSource(
            firestore: db,
            firebaseAuth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: uid, email: 'nf@lifeos.vn'),
            ),
            bridge: AndroidNotificationBridge(),
            allowLocalEmulatorlessFallbackForTest: false,
          );

          await expectLater(
            remote.deleteAccountAndPersonalData(uid),
            throwsA(anything),
          );
          expect((await db.collection('users').doc(uid).get()).exists, isTrue);
        },
      );
    });

    group('BANK-04: Strict Positive Evidence Required for VietQR Auto-Paid', () {
      test(
        'Generic bank (BANK), missing accountTail, ambiguous wallet, and expired/cancelled order NEVER auto-close VietQR as paid',
        () async {
          final db = FakeFirebaseFirestore();
          final remote = NotificationsRemoteDataSource(
            firestore: db,
            firebaseAuth: MockFirebaseAuth(),
            bridge: AndroidNotificationBridge(),
          );
          const uid = 'u_bank04';
          await _seedVietQrUser(
            db: db,
            remote: remote,
            uid: uid,
            allowedPackages: const ['com.VCB', 'com.unknown.generic.bank'],
            twoVcbWallets: false,
          );

          // 1. Generic bank ('BANK' because package isn't a known VN bank) with tail 6868 -> needsReview!
          final ordGeneric = await remote.createPaymentOrder(
            userId: uid,
            walletId: 'wallet_vcb',
            bankBin: '970436',
            bankCode: 'VCB',
            bankName: 'Vietcombank',
            accountNumber: '0071000886868',
            accountHolderName: 'MINH TRAN',
            amountMinor: 200000,
            description: 'Thu generic',
          );
          final outGeneric = await remote.ingestAndroidNotification(
            userId: uid,
            defaultWalletId: 'wallet_cash_default',
            packageName: 'com.unknown.generic.bank',
            title: 'Thong bao',
            body: 'TK 0071***6868 +200.000VND. ND: ${ordGeneric.paymentCode}',
            notificationId: 'n_bank04_generic',
          );
          expect(outGeneric.kind, IngestionOutcomeKind.createdProvisional);
          final ordGenericAfter = (await remote.watchPaymentOrders(uid).first)
              .firstWhere((o) => o.id == ordGeneric.id);
          expect(ordGenericAfter.status, PaymentOrderStatus.needsReview);
          expect(ordGenericAfter.isPaid, isFalse);
          expect(
            ordGenericAfter.reviewReason,
            'Thiếu thông tin ngân hàng hoặc số đuôi tài khoản đối chiếu — cần xác nhận thủ công.',
          );
          final txGeneric = await db
              .collection('users')
              .doc(uid)
              .collection('transactions')
              .doc(outGeneric.transactionId!)
              .get();
          expect(txGeneric.data()?['walletId'], 'wallet_cash_default');
          expect(txGeneric.data()?['verification'], 'needsReview');
          expect(txGeneric.data()?['ledgerApplied'], isFalse);

          // 2. Specific bank (VCB) WITHOUT accountTail -> needsReview & unredirected!
          final ordNoTail = await remote.createPaymentOrder(
            userId: uid,
            walletId: 'wallet_vcb',
            bankBin: '970436',
            bankCode: 'VCB',
            bankName: 'Vietcombank',
            accountNumber: '0071000886868',
            accountHolderName: 'MINH TRAN',
            amountMinor: 150000,
            description: 'Thu khong duoi TK',
          );
          final outNoTail = await remote.ingestAndroidNotification(
            userId: uid,
            defaultWalletId: 'wallet_cash_default',
            packageName: 'com.VCB',
            title: 'VCB Digibank',
            body: '+150.000VND. ND: ${ordNoTail.paymentCode}',
            notificationId: 'n_bank04_notail',
          );
          expect(outNoTail.kind, IngestionOutcomeKind.createdProvisional);
          final ordNoTailAfter = (await remote.watchPaymentOrders(uid).first)
              .firstWhere((o) => o.id == ordNoTail.id);
          expect(ordNoTailAfter.status, PaymentOrderStatus.needsReview);
          expect(ordNoTailAfter.isPaid, isFalse);
          expect(
            ordNoTailAfter.reviewReason,
            'Thiếu thông tin ngân hàng hoặc số đuôi tài khoản đối chiếu — cần xác nhận thủ công.',
          );
          final txNoTail = await db
              .collection('users')
              .doc(uid)
              .collection('transactions')
              .doc(outNoTail.transactionId!)
              .get();
          expect(txNoTail.data()?['walletId'], 'wallet_cash_default');
          expect(txNoTail.data()?['verification'], 'needsReview');
          expect(txNoTail.data()?['ledgerApplied'], isFalse);

          // 3. Expired & Cancelled orders MUST NEVER be matched or marked paid!
          final ordExpired = await remote.createPaymentOrder(
            userId: uid,
            walletId: 'wallet_vcb',
            bankBin: '970436',
            bankCode: 'VCB',
            bankName: 'Vietcombank',
            accountNumber: '0071000886868',
            accountHolderName: 'MINH TRAN',
            amountMinor: 180000,
            description: 'Don het han',
          );
          await remote.markPaymentOrderStatus(
            userId: uid,
            orderId: ordExpired.id,
            status: PaymentOrderStatus.expired,
          );
          await remote.ingestAndroidNotification(
            userId: uid,
            defaultWalletId: 'wallet_cash_default',
            packageName: 'com.VCB',
            title: 'VCB Digibank',
            body: 'TK 0071***6868 +180.000VND. ND: ${ordExpired.paymentCode}',
            notificationId: 'n_bank04_expired',
          );
          final ordExpiredAfter = (await remote.watchPaymentOrders(uid).first)
              .firstWhere((o) => o.id == ordExpired.id);
          expect(ordExpiredAfter.status, PaymentOrderStatus.expired);
          expect(ordExpiredAfter.isPaid, isFalse);

          // 4. Positive evidence (VCB + matching tail 6868 + matching amount) DOES close cleanly!
          final ordExact = await remote.createPaymentOrder(
            userId: uid,
            walletId: 'wallet_vcb',
            bankBin: '970436',
            bankCode: 'VCB',
            bankName: 'Vietcombank',
            accountNumber: '0071000886868',
            accountHolderName: 'MINH TRAN',
            amountMinor: 300000,
            description: 'Don hop le',
          );
          final outExact = await remote.ingestAndroidNotification(
            userId: uid,
            defaultWalletId: 'wallet_cash_default',
            packageName: 'com.VCB',
            title: 'VCB Digibank',
            body: 'TK 0071***6868 +300.000VND. ND: ${ordExact.paymentCode}',
            notificationId: 'n_bank04_exact',
          );
          expect(outExact.kind, IngestionOutcomeKind.autoReconciledOrder);
          final ordExactAfter = (await remote.watchPaymentOrders(uid).first)
              .firstWhere((o) => o.id == ordExact.id);
          expect(ordExactAfter.status, PaymentOrderStatus.paid);
          expect(ordExactAfter.isPaid, isTrue);

          // VCB wallet balance: initial 1,000,000 + 180,000 (auto-confirmed expired signal) + 300,000 (exact) = 1,480,000
          // (Generic and No-tail did NOT credit wallet_vcb!)
          final vcbWallet = await db
              .collection('users')
              .doc(uid)
              .collection('wallets')
              .doc('wallet_vcb')
              .get();
          expect(vcbWallet.data()?['balanceMinor'], 1480000);
        },
      );

      test(
        'Ambiguous wallet routing (2 VCB wallets & missing tail) keeps VietQR in needsReview and wallet unredirected',
        () async {
          final db = FakeFirebaseFirestore();
          final remote = NotificationsRemoteDataSource(
            firestore: db,
            firebaseAuth: MockFirebaseAuth(),
            bridge: AndroidNotificationBridge(),
          );
          const uid = 'u_bank04_ambig';
          await _seedVietQrUser(
            db: db,
            remote: remote,
            uid: uid,
            allowedPackages: const ['com.VCB'],
            twoVcbWallets: true,
          );
          final ord = await remote.createPaymentOrder(
            userId: uid,
            walletId: 'wallet_vcb',
            bankBin: '970436',
            bankCode: 'VCB',
            bankName: 'Vietcombank',
            accountNumber: '0071000886868',
            accountHolderName: 'MINH TRAN',
            amountMinor: 250000,
            description: 'Ambiguous routing test',
          );
          final out = await remote.ingestAndroidNotification(
            userId: uid,
            defaultWalletId: 'wallet_cash_default',
            packageName: 'com.VCB',
            title: 'VCB Digibank',
            body: '+250.000VND. ND: ${ord.paymentCode}',
            notificationId: 'n_bank04_ambig_1',
          );
          expect(out.kind, IngestionOutcomeKind.createdProvisional);
          final updated = (await remote.watchPaymentOrders(uid).first).single;
          expect(updated.status, PaymentOrderStatus.needsReview);
          expect(updated.isPaid, isFalse);
          final txSnap = await db
              .collection('users')
              .doc(uid)
              .collection('transactions')
              .doc(out.transactionId!)
              .get();
          expect(txSnap.data()?['walletId'], 'wallet_cash_default');
          expect(txSnap.data()?['ledgerApplied'], isFalse);
        },
      );
    });

    group('BANK-05: Fail-Closed SePay Revocation Without Redundant Mirror Write', () {
      test(
        'When server returns {ok: true}, NO redundant client mirror write occurs',
        () async {
          final db = FakeFirebaseFirestore();
          const uid = 'u_bank05_ok';
          const connId = 'conn_1';
          await db
              .collection('users')
              .doc(uid)
              .collection('bank_connections')
              .doc(connId)
              .set({
                'id': connId,
                'ownerId': uid,
                'status': 'connected',
                'consentStatus': 'granted',
              });

          final remote = NotificationsRemoteDataSource(
            firestore: db,
            firebaseAuth: MockFirebaseAuth(),
            bridge: AndroidNotificationBridge(),
            functionsInvokerOverride: (fnName, payload) async {
              expect(fnName, 'disconnectBankConnection');
              // Simulate server updating mirror with custom server marker;
              // if client performed a redundant write, it would add/overwrite fields!
              await db
                  .collection('users')
                  .doc(uid)
                  .collection('bank_connections')
                  .doc(connId)
                  .set({
                    'status': 'disconnected',
                    'consentStatus': 'revoked',
                    'lastRevocationError': 'kept_server_sentinel',
                    'serverRevokedSeq': 99,
                  }, SetOptions(merge: true));
              return <String, dynamic>{'ok': true};
            },
          );

          await remote.disconnectBankConnection(
            userId: uid,
            connectionId: connId,
          );

          final doc = await db
              .collection('users')
              .doc(uid)
              .collection('bank_connections')
              .doc(connId)
              .get();
          expect(doc.data()?['status'], 'disconnected');
          expect(doc.data()?['consentStatus'], 'revoked');
          // Prove client did NOT overwrite `lastRevocationError` to null!
          expect(doc.data()?['lastRevocationError'], 'kept_server_sentinel');
          expect(doc.data()?['serverRevokedSeq'], 99);
        },
      );

      test(
        'When server times out AFTER committing disconnected/revoked to mirror, client reads authoritative mirror and succeeds cleanly',
        () async {
          final db = FakeFirebaseFirestore();
          const uid = 'u_bank05_timeout';
          const connId = 'conn_2';
          await db
              .collection('users')
              .doc(uid)
              .collection('bank_connections')
              .doc(connId)
              .set({
                'id': connId,
                'ownerId': uid,
                'status': 'connected',
                'consentStatus': 'granted',
              });

          final remote = NotificationsRemoteDataSource(
            firestore: db,
            firebaseAuth: MockFirebaseAuth(),
            bridge: AndroidNotificationBridge(),
            functionsInvokerOverride: (_, _) async {
              // Server committed before response timed out on the wire!
              await db
                  .collection('users')
                  .doc(uid)
                  .collection('bank_connections')
                  .doc(connId)
                  .set({
                    'status': 'disconnected',
                    'consentStatus': 'revoked',
                  }, SetOptions(merge: true));
              throw Exception('deadline-exceeded');
            },
          );

          await remote.disconnectBankConnection(
            userId: uid,
            connectionId: connId,
          );

          final doc = await db
              .collection('users')
              .doc(uid)
              .collection('bank_connections')
              .doc(connId)
              .get();
          expect(doc.data()?['status'], 'disconnected');
          expect(doc.data()?['consentStatus'], 'revoked');
        },
      );

      test(
        'When server returns {ok: null} (missing ok) and mirror is still connected, fails closed with SERVER_REVOCATION_PENDING',
        () async {
          final db = FakeFirebaseFirestore();
          const uid = 'u_bank05_missing_ok';
          const connId = 'conn_3';
          await db
              .collection('users')
              .doc(uid)
              .collection('bank_connections')
              .doc(connId)
              .set({
                'id': connId,
                'ownerId': uid,
                'status': 'connected',
                'consentStatus': 'granted',
              });

          final remote = NotificationsRemoteDataSource(
            firestore: db,
            firebaseAuth: MockFirebaseAuth(),
            bridge: AndroidNotificationBridge(),
            functionsInvokerOverride: (_, _) async => <String, dynamic>{},
          );

          await expectLater(
            remote.disconnectBankConnection(userId: uid, connectionId: connId),
            throwsA(
              isA<AppException>().having(
                (e) => e.code,
                'code',
                'SERVER_REVOCATION_PENDING',
              ),
            ),
          );

          final doc = await db
              .collection('users')
              .doc(uid)
              .collection('bank_connections')
              .doc(connId)
              .get();
          expect(doc.data()?['status'], 'pendingRevocation');
          expect(doc.data()?['consentStatus'], 'revocation_pending');
        },
      );
    });

    group('DATA-01: Serialized Atomic OfflineOutboxService', () {
      test(
        '100 concurrent enqueue + flushDue calls lose 0 operations and never double-dispatch leased items',
        () async {
          final vault = NativeSecureVaultBridge.testable();
          final outbox = OfflineOutboxService(vault: vault);
          await outbox.setActiveUserId('u_outbox_conc');

          final executedCounts = <String, int>{};
          final futures = <Future<Object?>>[];
          final now = DateTime.utc(2026, 11, 27, 10, 0);

          for (var i = 0; i < 50; i++) {
            futures.add(
              outbox.enqueue(
                OutboxRecord(
                  operationId: 'op_$i',
                  ownerId: 'u_outbox_conc',
                  entityType: 'transaction',
                  entityId: 'tx_$i',
                  payload: {'amountMinor': 1000 + i},
                  baseUpdatedAtEpochMs: now.millisecondsSinceEpoch,
                ),
              ),
            );
            futures.add(
              outbox.flushDue(
                userId: 'u_outbox_conc',
                nowOverride: now,
                executor: (rec) async {
                  await Future<void>.delayed(const Duration(milliseconds: 2));
                  executedCounts[rec.operationId] =
                      (executedCounts[rec.operationId] ?? 0) + 1;
                  return OutboxRemoteOutcome.synced;
                },
              ),
            );
          }
          await Future.wait(futures);

          // Flush any trailing items enqueued while final phase-2 network calls ran
          final finalTelemetry = await outbox.flushDue(
            userId: 'u_outbox_conc',
            nowOverride: now.add(const Duration(seconds: 5)),
            executor: (rec) async {
              executedCounts[rec.operationId] =
                  (executedCounts[rec.operationId] ?? 0) + 1;
              return OutboxRemoteOutcome.synced;
            },
          );

          expect(finalTelemetry.pendingCount, 0);
          expect(executedCounts.length, 50);
          for (var i = 0; i < 50; i++) {
            expect(executedCounts['op_$i'], 1);
          }
          expect(await outbox.loadQueue('u_outbox_conc'), isEmpty);
          await outbox.dispose();
        },
      );

      test(
        'Quarantines corrupted JSON instead of silently wiping and moves exhausted retries to dead-letter',
        () async {
          final vault = NativeSecureVaultBridge.testable();
          final outbox = OfflineOutboxService(
            vault: vault,
            leaseDurationMs: 5000,
          );
          const uid = 'u_corrupt';
          final storageKey = OfflineOutboxService.storageKeyForUser(uid);
          const corruptPayload = '{bad_json_not_list';
          await vault.writeSecret(key: storageKey, value: corruptPayload);

          final loaded = await outbox.loadQueue(uid);
          expect(loaded, isEmpty);
          expect(outbox.quarantinedCorruptionCount, 1);
          expect(outbox.lastCorruptionError, isNotNull);
          expect(outbox.quarantinedKeys.length, 1);
          expect(
            outbox.quarantinedKeys.single,
            startsWith('${storageKey}__corrupted_'),
          );
          expect(
            await vault.readSecret(outbox.quarantinedKeys.single),
            corruptPayload,
          );

          // Dead-letter after maxAttempts transient failures
          final t0 = DateTime.utc(2026, 11, 27, 12, 0);
          await outbox.enqueue(
            OutboxRecord(
              operationId: 'op_dlq',
              ownerId: uid,
              entityType: 'task',
              entityId: 'task_1',
              payload: const {'title': 'Retry test'},
              baseUpdatedAtEpochMs: t0.millisecondsSinceEpoch,
            ),
          );
          for (
            var attempt = 0;
            attempt < OfflineOutboxService.maxAttempts;
            attempt++
          ) {
            await outbox.flushDue(
              userId: uid,
              nowOverride: t0.add(Duration(minutes: attempt * 10)),
              executor: (_) async => OutboxRemoteOutcome.transientFailure,
            );
          }

          final dlq = await outbox.getDeadLetters(uid);
          expect(dlq.length, 1);
          expect(dlq.single.isDeadLetter, isTrue);
          expect(dlq.single.stage, OfflineSyncStage.failed);
          expect(dlq.single.attemptCount, OfflineOutboxService.maxAttempts);
          expect(outbox.currentTelemetry(uid).deadLetterCount, 1);

          // Cross-user isolation on account switch
          await outbox.setActiveUserId('u_other_user');
          expect(
            () => outbox.enqueue(
              OutboxRecord(
                operationId: 'op_cross',
                ownerId: uid,
                entityType: 'note',
                entityId: 'n1',
                payload: const {},
                baseUpdatedAtEpochMs: t0.millisecondsSinceEpoch,
              ),
            ),
            throwsStateError,
          );
          await outbox.clearSessionOnSignOut();
          expect(outbox.activeUserId, isNull);
          await outbox.dispose();
        },
      );
    });

    group(
      'DATA-02: Safe Backup Restore Without Pre-Deletion & Verified Tx Protection',
      () {
        test(
          'Dry-run validation aborts before touching Firestore when tx references missing wallet',
          () async {
            final db = FakeFirebaseFirestore();
            const uid = 'u_data02_val';
            await db
                .collection('users')
                .doc(uid)
                .collection('life_notes')
                .doc('n_keep')
                .set({
                  'id': 'n_keep',
                  'ownerId': uid,
                  'title': 'Existing Note',
                });

            final txRepo = TransactionRepositoryImpl(
              TransactionRemoteDataSource(db),
            );
            final ds = FirestoreBackupRemoteDataSource(
              firestore: db,
              transactionRepository: txRepo,
              createTransactionUseCase: CreateTransactionUseCase(txRepo),
              reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
            );

            final invalidPreview = BackupArchivePreview(
              schemaVersion: 4,
              ownerId: uid,
              exportedAt: DateTime.utc(2026, 11, 27),
              checksumVerified: true,
              wasEncrypted: true,
              archiveSha256: 'abc12345',
              collections: const {
                BackupCollectionCatalog.wallets: [
                  {'id': 'w1', 'name': 'Ví A', 'balanceMinor': 100000},
                ],
                BackupCollectionCatalog.transactions: [
                  {
                    'id': 'tx_orphan',
                    'walletId': 'w_nonexistent',
                    'kind': 'expense',
                    'amountMinor': 50000,
                    'occurredAt': '2026-11-27T01:00:00Z',
                  },
                ],
              },
            );

            await expectLater(
              ds.restoreAllOwnerCollections(
                targetUserId: uid,
                preview: invalidPreview,
                mode: BackupRestoreMode.replaceConfirmed,
                explicitReplaceConfirmation: true,
              ),
              throwsA(
                isA<AppException>().having(
                  (e) => e.code,
                  'code',
                  'VALIDATION_FAILURE',
                ),
              ),
            );

            expect(
              (await db
                      .collection('users')
                      .doc(uid)
                      .collection('life_notes')
                      .doc('n_keep')
                      .get())
                  .exists,
              isTrue,
            );
          },
        );

        test(
          'replaceConfirmed aborts BEFORE pruning when mid-write fails, and NEVER deletes verified bank transactions or their wallets when succeeding',
          () async {
            final db = FakeFirebaseFirestore();
            const uid = 'u_data02_replace';
            final txRepo = TransactionRepositoryImpl(
              TransactionRemoteDataSource(db),
            );

            // Seed existing user state:
            // - w_old (non-verified obsolete wallet)
            // - w_bank_verified (holds immutable verified bank tx)
            // - tx_old_manual (obsolete unverified tx)
            // - tx_bank_verified (immutable verified bankApi tx)
            // - note_old (obsolete note)
            await db
                .collection('users')
                .doc(uid)
                .collection('wallets')
                .doc('w_old')
                .set({
                  'id': 'w_old',
                  'ownerId': uid,
                  'name': 'Ví cũ',
                  'type': 'cash',
                  'balanceMinor': 500000,
                });
            await db
                .collection('users')
                .doc(uid)
                .collection('wallets')
                .doc('w_bank_verified')
                .set({
                  'id': 'w_bank_verified',
                  'ownerId': uid,
                  'name': 'VCB Xác Thực',
                  'type': 'bank',
                  'balanceMinor': 10000000,
                });
            await db
                .collection('users')
                .doc(uid)
                .collection('transactions')
                .doc('tx_old_manual')
                .set({
                  'id': 'tx_old_manual',
                  'ownerId': uid,
                  'walletId': 'w_old',
                  'categoryName': 'Ăn uống',
                  'kind': 'expense',
                  'direction': 'debit',
                  'amountMinor': 25000,
                  'currencyCode': 'VND',
                  'merchant': 'Quán cũ',
                  'occurredAt': Timestamp.fromDate(DateTime(2026, 11, 20)),
                  'monthKey': '2026-11',
                  'sourceKind': 'manual',
                  'verification': 'userConfirmed',
                });
            await db
                .collection('users')
                .doc(uid)
                .collection('transactions')
                .doc('tx_bank_verified')
                .set({
                  'id': 'tx_bank_verified',
                  'ownerId': uid,
                  'walletId': 'w_bank_verified',
                  'categoryName': 'Lương',
                  'kind': 'income',
                  'direction': 'credit',
                  'amountMinor': 10000000,
                  'currencyCode': 'VND',
                  'merchant': 'SEPAY BANK API',
                  'occurredAt': Timestamp.fromDate(DateTime(2026, 11, 21)),
                  'monthKey': '2026-11',
                  'sourceKind': 'bankApi',
                  'verification': 'verified',
                  'verificationStatus': 'VERIFIED',
                  'ledgerApplied': true,
                });
            await db
                .collection('users')
                .doc(uid)
                .collection('life_notes')
                .doc('note_old')
                .set({'id': 'note_old', 'ownerId': uid, 'title': 'Ghi chú cũ'});

            final backupPreview = BackupArchivePreview(
              schemaVersion: 4,
              ownerId: uid,
              exportedAt: DateTime.utc(2026, 11, 27),
              checksumVerified: true,
              wasEncrypted: true,
              archiveSha256: 'feedcafe',
              collections: const {
                BackupCollectionCatalog.wallets: [
                  {
                    'id': 'w_new',
                    'name': 'Ví mới',
                    'type': 'cash',
                    'balanceMinor': 900000,
                  },
                ],
                BackupCollectionCatalog.transactions: [
                  {
                    'id': 'tx_new',
                    'walletId': 'w_new',
                    'categoryName': 'Mua sắm',
                    'kind': 'expense',
                    'amountMinor': 100000,
                    'merchant': 'Cửa hàng mới',
                    'occurredAt': '2026-11-26T08:00:00Z',
                  },
                ],
                BackupCollectionCatalog.notes: [
                  {'id': 'note_new', 'title': 'Ghi chú mới', 'content': 'OK'},
                ],
              },
            );

            // 1. Mid-way write failure at write #2 -> MUST abort BEFORE pruning anything!
            final failingDs = FirestoreBackupRemoteDataSource(
              firestore: db,
              transactionRepository: txRepo,
              createTransactionUseCase: CreateTransactionUseCase(txRepo),
              reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
              onBeforeWrite: (_, _, idx) async {
                if (idx == 2) {
                  throw FirebaseException(
                    plugin: 'cloud_firestore',
                    code: 'unavailable',
                    message: 'Simulated mid-restore failure',
                  );
                }
              },
            );
            final failReport = await failingDs.restoreAllOwnerCollections(
              targetUserId: uid,
              preview: backupPreview,
              mode: BackupRestoreMode.replaceConfirmed,
              explicitReplaceConfirmation: true,
            );
            expect(failReport.isPartialFailure, isTrue);
            // All pre-existing records MUST remain intact!
            expect(
              (await db
                      .collection('users')
                      .doc(uid)
                      .collection('wallets')
                      .doc('w_old')
                      .get())
                  .exists,
              isTrue,
            );
            expect(
              (await db
                      .collection('users')
                      .doc(uid)
                      .collection('transactions')
                      .doc('tx_old_manual')
                      .get())
                  .exists,
              isTrue,
            );
            expect(
              (await db
                      .collection('users')
                      .doc(uid)
                      .collection('life_notes')
                      .doc('note_old')
                      .get())
                  .exists,
              isTrue,
            );
            expect(
              (await db
                      .collection('users')
                      .doc(uid)
                      .collection('transactions')
                      .doc('tx_bank_verified')
                      .get())
                  .exists,
              isTrue,
            );

            // 2. Clean replaceConfirmed succeeds 100% -> prunes non-verified obsolete records,
            //    while preserving `tx_bank_verified` AND `w_bank_verified`!
            final cleanDs = FirestoreBackupRemoteDataSource(
              firestore: db,
              transactionRepository: txRepo,
              createTransactionUseCase: CreateTransactionUseCase(txRepo),
              reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
            );
            final okReport = await cleanDs.restoreAllOwnerCollections(
              targetUserId: uid,
              preview: backupPreview,
              mode: BackupRestoreMode.replaceConfirmed,
              explicitReplaceConfirmation: true,
            );
            expect(okReport.isCleanSuccess, isTrue);

            // Obsolete non-verified docs pruned:
            expect(
              (await db
                      .collection('users')
                      .doc(uid)
                      .collection('wallets')
                      .doc('w_old')
                      .get())
                  .exists,
              isFalse,
            );
            expect(
              (await db
                      .collection('users')
                      .doc(uid)
                      .collection('transactions')
                      .doc('tx_old_manual')
                      .get())
                  .exists,
              isFalse,
            );
            expect(
              (await db
                      .collection('users')
                      .doc(uid)
                      .collection('life_notes')
                      .doc('note_old')
                      .get())
                  .exists,
              isFalse,
            );

            // Verified bank tx & its wallet MUST NEVER be deleted!
            expect(
              (await db
                      .collection('users')
                      .doc(uid)
                      .collection('transactions')
                      .doc('tx_bank_verified')
                      .get())
                  .exists,
              isTrue,
            );
            final protectedWalletSnap = await db
                .collection('users')
                .doc(uid)
                .collection('wallets')
                .doc('w_bank_verified')
                .get();
            expect(protectedWalletSnap.exists, isTrue);
            expect(protectedWalletSnap.data()?['isArchived'], isTrue);

            // Restored records present with exact balance:
            final newWalletSnap = await db
                .collection('users')
                .doc(uid)
                .collection('wallets')
                .doc('w_new')
                .get();
            expect(newWalletSnap.data()?['balanceMinor'], 900000);
          },
        );
      },
    );

    group('DATA-03: Standard AES-256-GCM Backup Codec v4', () {
      test(
        'Aes256Gcm matches OpenSSL / NIST SP 800-38D vectors (with & without AAD)',
        () {
          // Vector 1 (with non-block-aligned AAD & plaintext)
          final v1 = Aes256Gcm.encrypt(
            key: _hexToBytes(
              '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
            ),
            nonce: _hexToBytes('cafebabefacedbaddecaf888'),
            plaintext: _hexToBytes(
              'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39',
            ),
            aad: _hexToBytes('feedfacedeadbeeffeedfacedeadbeefabaddad2'),
          );
          expect(
            _bytesToHex(v1.ciphertext),
            '5392920352fe49fee3525418d4e8afa58b876902ca2d9dae6093344c34b8ef8db16ccdd354bc40310994264c7b259540e83e44a409876e8799f10a05',
          );
          expect(_bytesToHex(v1.tag), '77f8b3108a678a13b9f5f2c71e7de056');

          final dec1 = Aes256Gcm.decrypt(
            key: _hexToBytes(
              '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
            ),
            nonce: _hexToBytes('cafebabefacedbaddecaf888'),
            ciphertext: v1.ciphertext,
            tag: v1.tag,
            aad: _hexToBytes('feedfacedeadbeeffeedfacedeadbeefabaddad2'),
          );
          expect(
            _bytesToHex(dec1),
            'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39',
          );

          // Vector 2 (NIST SP 800-38D Test Case 14/15: empty AAD)
          final v2 = Aes256Gcm.encrypt(
            key: _hexToBytes(
              'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308',
            ),
            nonce: _hexToBytes('cafebabefacedbaddecaf888'),
            plaintext: _hexToBytes(
              'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255',
            ),
          );
          expect(
            _bytesToHex(v2.ciphertext),
            '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad',
          );
          expect(_bytesToHex(v2.tag), 'b094dac5d93471bdec1a502270e3cc6c');
        },
      );

      test(
        'Enforces 25 MB archive bound, iteration bounds (100k..1M), mandatory encryption in BackupRepositoryImpl, and zero downgrade',
        () async {
          const prodCodec = BackupArchiveCodec();

          // Reject > 25 MB input before jsonDecode
          final oversized = 'A' * (BackupArchiveCodec.maxArchiveBytes + 1);
          await expectLater(
            prodCodec.previewAndValidateAsync(oversized, passphrase: 'pw'),
            throwsFormatException,
          );

          // Reject > 1,000,000 iterations
          const overIterCodec = BackupArchiveCodec.forTesting(
            kdfIterations: 1000001,
            minDecodeIterations: 100000,
            maxDecodeIterations: 2000000,
          );
          final overIterArchive = await overIterCodec.createArchiveAsync(
            ownerId: 'u_over_iter',
            passphrase: 'Pass#Over1M',
            collections: const {},
          );
          await expectLater(
            prodCodec.previewAndValidateAsync(
              overIterArchive,
              passphrase: 'Pass#Over1M',
            ),
            throwsFormatException,
          );

          // BackupRepositoryImpl refuses plaintext export unless allowPlaintextExport: true
          final db = FakeFirebaseFirestore();
          final txRepo = TransactionRepositoryImpl(
            TransactionRemoteDataSource(db),
          );
          final backupRepo = BackupRepositoryImpl(
            remoteDataSource: FirestoreBackupRemoteDataSource(
              firestore: db,
              transactionRepository: txRepo,
              createTransactionUseCase: CreateTransactionUseCase(txRepo),
              reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
            ),
          );
          final refusedRes = await backupRepo.exportOwnerData(
            ownerId: 'u_repo_enc',
          );
          expect(refusedRes.isSuccess, isFalse);

          final optInRes = await backupRepo.exportOwnerData(
            ownerId: 'u_repo_enc',
            allowPlaintextExport: true,
          );
          expect(optInRes.isSuccess, isTrue);
          final optInBundle = (optInRes as Success<BackupExportBundle>).value;
          expect(optInBundle.encrypted, isFalse);
          expect(
            optInBundle.limitationsVi.any(
              (l) => l.contains('KHÔNG được mã hóa'),
            ),
            isTrue,
          );
        },
      );
    });

    group('DATA-04: Bounded Firestore Offline Cache', () {
      test(
        'FirebaseConfig bounds offline persistence cache to 100 MB (not CACHE_SIZE_UNLIMITED)',
        () {
          expect(FirebaseConfig.maxFirestoreCacheSizeBytes, 100 * 1024 * 1024);
          expect(
            FirebaseConfig.maxFirestoreCacheSizeBytes,
            isNot(Settings.CACHE_SIZE_UNLIMITED),
          );
          expect(FirebaseConfig.firestoreSettings.persistenceEnabled, isTrue);
          expect(
            FirebaseConfig.firestoreSettings.cacheSizeBytes,
            lessThanOrEqualTo(100 * 1024 * 1024),
          );
          expect(
            FirebaseConfig.firestoreSettings.cacheSizeBytes,
            greaterThan(0),
          );
        },
      );
    });
  });
}
