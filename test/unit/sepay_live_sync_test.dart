import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/features/authentication/domain/entities/user_entity.dart';
import 'package:life_os/features/authentication/domain/repositories/auth_repository.dart';
import 'package:life_os/features/notifications/data/datasources/sepay_api_datasource.dart';
import 'package:life_os/features/notifications/presentation/bloc/notification_ingestion_bloc.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/domain/repositories/transaction_repository.dart';

void main() {
  group('SePay Live REST API Sync & Real-World Bank Reconciliation', () {
    test('SePayApiDataSource parses official my.sepay.vn/userapi/transactions/list JSON accurately', () async {
      final mockClient = MockClient((req) async {
        expect(req.url.toString(), contains('https://my.sepay.vn/userapi/transactions/list'));
        expect(req.headers['Authorization'], 'Bearer sp_live_secret_9876');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'status': 200,
              'messages': {'success': true},
              'transactions': [
                {
                  'id': '99012',
                  'bank_brand_name': 'Vietcombank',
                  'account_number': '00710008868',
                  'transaction_date': '2026-11-22 18:30:00',
                  'amount_out': '0.00',
                  'amount_in': '1500000.00',
                  'accumulated': '26350000.00',
                  'transaction_content': 'SEVQR HOAN TIEN NHOM DA LAT',
                  'reference_number': 'FT2632611990',
                },
                {
                  'id': '99011',
                  'bank_brand_name': 'Vietcombank',
                  'account_number': '00710008868',
                  'transaction_date': '2026-11-22 12:05:10',
                  'amount_out': '95000.00',
                  'amount_in': '0.00',
                  'accumulated': '24850000.00',
                  'transaction_content': 'Thanh toan Highlands Coffee',
                  'reference_number': 'FT2632611002',
                },
              ],
            }),
          ),
          200,
        );
      });

      final ds = SePayApiDataSource(httpClient: mockClient);
      final list = await ds.fetchRecentTransactions(apiToken: 'sp_live_secret_9876');

      expect(list.length, 2);
      // Sorted chronologically oldest -> newest
      expect(list.first.externalId, 'sepay_99011');
      expect(list.first.direction, 'debit');
      expect(list.first.amountMinor, 95000);
      expect(list.last.externalId, 'sepay_99012');
      expect(list.last.direction, 'credit');
      expect(list.last.amountMinor, 1500000);
      expect(list.last.referenceCode, 'FT2632611990');
    });

    test('NotificationIngestionBloc SePayLiveSyncSubmitted reconciles real SePay feed into Firestore & masks saved token', () async {
      final mockAuth = MockFirebaseAuth();
      final fakeFirestore = FakeFirebaseFirestore();
      final now = DateTime.now();
      final dtStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} 10:15:00';

      final mockClient = MockClient((req) async {
        if (req.url.host == 'my.sepay.vn') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'status': 200,
                'transactions': [
                  {
                    'id': '55101',
                    'bank_brand_name': 'MBBank',
                    'account_number': '0909123456',
                    'transaction_date': dtStr,
                    'amount_out': '165000.00',
                    'amount_in': '0.00',
                    'accumulated': '9835000.00',
                    'transaction_content': 'Bach Hoa Xanh Mua Nuoc Giat',
                    'reference_number': 'MB998811',
                  },
                ],
              }),
            ),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      await configureDependencies(
        authOverride: mockAuth,
        firestoreOverride: fakeFirestore,
        httpClientOverride: mockClient,
      );

      final signUp = await sl<AuthRepository>().signUp(
        email: 'sepay@lifeos.vn',
        password: 'Password123!',
        fullName: 'Hoàng SePay',
      );
      final user = (signUp as Success<UserEntity>).value;

      final bloc = sl<NotificationIngestionBloc>()
        ..add(NotificationsCenterStarted(user.id, defaultWalletId: 'wallet_bank_default'));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      bloc.add(
        SePayLiveSyncSubmitted(
          userId: user.id,
          walletId: 'wallet_bank_default',
          apiTokenOverride: 'sepay_prod_token_abcd',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(bloc.state.savedSePayMaskedToken, '••••••••••••abcd');
      expect(bloc.state.infoMessage, contains('1 giao dịch mới trực tiếp từ SePay'));

      // Re-running sync with saved token (no override) is idempotent (0 duplicates!)
      bloc.add(
        SePayLiveSyncSubmitted(
          userId: user.id,
          walletId: 'wallet_bank_default',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(bloc.state.infoMessage, contains('0 giao dịch mới'));

      final monthKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
      final txs = (await sl<TransactionRepository>()
                  .watchTransactions(userId: user.id, monthKey: monthKey)
                  .first
              as Success<List<TransactionEntity>>)
          .value;
      expect(txs.length, 1);
      expect(txs.single.verification, TransactionVerification.verified);
      expect(txs.single.amountMinor, 165000);
      expect(txs.single.balanceAfterMinor, -165000);

      await bloc.close();
    });
  });
}
