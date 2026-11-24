import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/security/bank_notification_parser.dart';
import 'package:life_os/core/utils/vietqr_emv_builder.dart';
import 'package:life_os/features/authentication/domain/entities/user_entity.dart';
import 'package:life_os/features/authentication/domain/repositories/auth_repository.dart';
import 'package:life_os/features/notifications/domain/entities/notification_entities.dart';
import 'package:life_os/features/notifications/presentation/bloc/notification_ingestion_bloc.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/domain/repositories/transaction_repository.dart';

void main() {
  group(
    'Native In-App Payment Recognition, Dynamic VietQR EMVCo & Auto-Reconciliation (v3.3)',
    () {
      test('Zero external my.sepay.vn API calls remain anywhere in lib/', () {
        final dartFiles = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();

        final violations = <String>[];
        for (final f in dartFiles) {
          final content = f.readAsStringSync();
          if (content.contains('my.sepay.vn')) {
            violations.add(f.path);
          }
        }
        expect(
          violations,
          isEmpty,
          reason: 'Found external SePay API URL in: $violations',
        );
      });

      test(
        'VietQrEmvBuilder computes ISO CRC16-CCITT and builds valid NAPAS 247 QRIBFTTA payload',
        () {
          // Official ISO/IEC 13239 CRC-16/CCITT-FALSE standard test vector
          expect(VietQrEmvBuilder.crc16CcittHex('123456789'), '29B1');

          final emv = VietQrEmvBuilder.buildNapas247Payload(
            bankBin: '970436',
            accountNumber: '0071000886868',
            amountVnd: 250000,
            memo: 'LO482910 Tien dien T11',
          );

          expect(emv, startsWith('00020101021238'));
          expect(emv, contains('A000000727'));
          expect(emv, contains('970436'));
          expect(emv, contains('0071000886868'));
          expect(emv, contains('QRIBFTTA'));
          expect(emv, contains('5303704'));
          expect(emv, contains('5406250000'));
          expect(emv, contains('5802VN'));
          expect(emv, contains('LO482910 TIEN DIEN T11'));

          // Verify trailing 4-hex CRC matches body up to `6304`
          final bodyUpTo6304 = emv.substring(0, emv.length - 4);
          final expectedCrc = VietQrEmvBuilder.crc16CcittHex(bodyUpTo6304);
          expect(emv.substring(emv.length - 4), expectedCrc);
        },
      );

      test(
        'BankNotificationParser extracts SD post-tx balance, accountTail & LifeOS QR payment code across 18+ banks',
        () {
          expect(kSupportedVnBanks.length, greaterThanOrEqualTo(18));

          final parsed = BankNotificationParser.parseAndroidNotification(
            ownerId: 'u_qr_1',
            packageName: 'com.VCB',
            title: 'VCB Digibank',
            body:
                'TK 0071***6868 GD: +450.000VND 23/11/2026 14:20. ND: Nguyen Minh chuyen khoan LO8K4P92. SD: 18.450.000VND',
          );

          expect(parsed.signal, isNotNull);
          expect(parsed.signal!.direction, 'credit');
          expect(parsed.signal!.amountMinor, 450000);
          expect(parsed.signal!.observedBalanceMinor, 18450000);
          expect(parsed.signal!.accountTail, '6868');
          expect(parsed.signal!.matchedPaymentCode, 'LO8K4P92');
        },
      );

      test(
        'End-to-End Native Payment Gateway: Link Bank -> Create QR Order -> Incoming Bank Push Auto-Reconciles Order & Syncs Exact SD Balance',
        () async {
          final mockAuth = MockFirebaseAuth();
          final fakeFirestore = FakeFirebaseFirestore();
          final now = DateTime.now();

          await configureDependencies(
            authOverride: mockAuth,
            firestoreOverride: fakeFirestore,
            httpClientOverride: MockClient(
              (_) async => http.Response('{}', 404),
            ),
          );

          final signUp = await sl<AuthRepository>().signUp(
            email: 'gateway@lifeos.vn',
            password: 'Password123!',
            fullName: 'Trần Minh',
          );
          final user = (signUp as Success<UserEntity>).value;

          final bloc = sl<NotificationIngestionBloc>()
            ..add(
              NotificationsCenterStarted(
                user.id,
                defaultWalletId: 'wallet_bank_default',
              ),
            );
          await Future<void>.delayed(const Duration(milliseconds: 60));

          // 1. Enable native bank notification recognition across all supported VN banks
          bloc.add(
            ConsentConfigUpdated(
              userId: user.id,
              enabled: true,
              allowedPackages: kSupportedVnBanks
                  .map((b) => b.packageName)
                  .toList(),
              autoConfirmSignals: true,
              voiceSoundboxEnabled: true,
            ),
          );

          // 2. Link user's own Vietcombank receiving account (zero external API token!)
          bloc.add(
            LinkedBankAccountSaved(
              userId: user.id,
              walletId: 'wallet_bank_default',
              bankBin: '970436',
              bankCode: 'VCB',
              bankName: 'Vietcombank',
              accountNumber: '0071000886868',
              accountHolderName: 'TRAN MINH',
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 80));

          expect(bloc.state.linkedBankAccounts.length, 1);
          expect(bloc.state.defaultBankAccount!.maskedAccount, '•••• 6868');

          // 3. Create an in-app Dynamic VietQR collection order for 320,000 VND
          bloc.add(
            PaymentOrderCreated(
              userId: user.id,
              walletId: 'wallet_bank_default',
              bankBin: '970436',
              bankCode: 'VCB',
              bankName: 'Vietcombank',
              accountNumber: '0071000886868',
              accountHolderName: 'TRAN MINH',
              amountMinor: 320000,
              description: 'Tiền điện tháng 11',
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 80));

          expect(bloc.state.paymentOrders.length, 1);
          final createdOrder = bloc.state.paymentOrders.single;
          expect(createdOrder.status, PaymentOrderStatus.pending);
          expect(createdOrder.paymentCode, startsWith('LO'));

          // 4. Incoming Vietcombank push notification arrives carrying `createdOrder.paymentCode` and `SD: 12.320.000VND`
          bloc.add(
            BankNotificationSignalReceived(
              userId: user.id,
              defaultWalletId:
                  'wallet_cash_default', // Routed automatically to wallet_bank_default via accountTail 6868!
              packageName: 'com.VCB',
              title: 'VCB Digibank',
              body:
                  'TK 0071***6868 GD: +320.000VND. ND: Lan chuyen tien ${createdOrder.paymentCode}. SD: 12.320.000VND',
              postedAt: now,
              notificationId: 'notif_qr_match_1',
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 120));

          // Verify QR order flipped automatically to PAID (`Đã nhận đủ`)!
          expect(
            bloc.state.lastOutcome?.kind,
            IngestionOutcomeKind.autoReconciledOrder,
          );
          expect(bloc.state.paymentOrders.single.isPaid, isTrue);
          expect(bloc.state.paymentOrders.single.receivedAmountMinor, 320000);

          // Verify Wallet balance synced to exact `SD: 12.320.000 ₫` and ledger transaction is `verified`!
          final wallets =
              (await sl<TransactionRepository>().watchWallets(user.id).first
                      as Success<List<WalletEntity>>)
                  .value;
          final bankWallet = wallets.firstWhere(
            (w) => w.id == 'wallet_bank_default',
          );
          expect(bankWallet.balanceMinor, 12320000);
          expect(bankWallet.isEstimatedBalance, isFalse);

          final monthKey =
              '${now.toUtc().year.toString().padLeft(4, '0')}-${now.toUtc().month.toString().padLeft(2, '0')}';
          final txs =
              (await sl<TransactionRepository>()
                          .watchTransactions(
                            userId: user.id,
                            monthKey: monthKey,
                          )
                          .first
                      as Success<List<TransactionEntity>>)
                  .value;
          expect(txs.length, 1);
          expect(
            txs.single.verification,
            TransactionVerification.matchedPaymentOrder,
          );
          expect(txs.single.amountMinor, 320000);
          expect(txs.single.categoryName, 'Thu tiền QR');

          await bloc.close();
        },
      );
    },
  );
}
