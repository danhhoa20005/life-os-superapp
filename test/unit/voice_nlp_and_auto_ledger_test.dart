import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/utils/voice_financial_nlp_engine.dart';
import 'package:life_os/features/authentication/domain/entities/user_entity.dart';
import 'package:life_os/features/authentication/domain/repositories/auth_repository.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/domain/repositories/transaction_repository.dart';

void main() {
  group('Voice Financial NLP Sentence Analyzer & Zero-Touch Auto-Ledger', () {
    test(
      'Parses spoken Vietnamese equal group split by headcount and named members',
      () {
        final res1 = VoiceFinancialNlpEngine.analyze(
          'Ăn lẩu bò bốn trăm năm mươi nghìn chia đều 3 người',
          currentUserId: 'u_hoa',
          currentUserName: 'Danh Hòa',
        );
        expect(res1, isNotNull);
        expect(res1!.intentKind, VoiceSentenceIntentKind.groupBillSplit);
        expect(res1.groupSplit!.totalAmountMinor, 450000);
        expect(res1.groupSplit!.topic, SharedExpenseTopic.dining);
        expect(res1.groupSplit!.splitMethod, SplitMethod.equal);
        expect(res1.groupSplit!.shares.length, 3);
        expect(
          res1.groupSplit!.shares.every((s) => s.amountMinor == 150000),
          isTrue,
        );

        final res2 = VoiceFinancialNlpEngine.analyze(
          'Tiền điện nước 1 triệu 2 chia cho Hòa, Minh và Lan',
          currentUserId: 'u_hoa',
          currentUserName: 'Hòa',
        );
        expect(res2, isNotNull);
        expect(res2!.groupSplit!.totalAmountMinor, 1200000);
        expect(res2.groupSplit!.topic, SharedExpenseTopic.utilities);
        expect(res2.groupSplit!.shares.map((s) => s.displayName).toList(), [
          'Hòa',
          'Minh',
          'Lan',
        ]);
        expect(
          res2.groupSplit!.shares.every((s) => s.amountMinor == 400000),
          isTrue,
        );
      },
    );

    test(
      'Parses spoken remainder split ("còn lại ... chịu") and percentage split ("phần trăm")',
      () {
        final rem = VoiceFinancialNlpEngine.analyze(
          'Ăn tối 500 nghìn Minh 200 nghìn còn lại Hòa chịu',
          currentUserId: 'u_hoa',
          currentUserName: 'Hòa',
        );
        expect(rem, isNotNull);
        expect(rem!.intentKind, VoiceSentenceIntentKind.groupBillSplit);
        expect(rem.groupSplit!.splitMethod, SplitMethod.exact);
        expect(rem.groupSplit!.shares.length, 2);
        expect(rem.groupSplit!.shares[0].displayName, 'Minh');
        expect(rem.groupSplit!.shares[0].amountMinor, 200000);
        expect(rem.groupSplit!.shares[1].displayName, 'Hòa');
        expect(rem.groupSplit!.shares[1].amountMinor, 300000);

        final pct = VoiceFinancialNlpEngine.analyze(
          'Tiền thuê nhà 8 triệu Hòa 60 phần trăm Minh 40 phần trăm',
          currentUserId: 'u_hoa',
          currentUserName: 'Hòa',
        );
        expect(pct, isNotNull);
        expect(pct!.groupSplit!.splitMethod, SplitMethod.percentage);
        expect(pct.groupSplit!.shares[0].amountMinor, 4800000);
        expect(pct.groupSplit!.shares[1].amountMinor, 3200000);
      },
    );

    test(
      'Parses multi-category supermarket receipt split & 3-item batch spoken sentence',
      () {
        final receipt = VoiceFinancialNlpEngine.analyze(
          'Đi siêu thị 500 nghìn gồm ăn uống 320 nghìn và việc nhà 180 nghìn',
        );
        expect(receipt, isNotNull);
        expect(
          receipt!.intentKind,
          VoiceSentenceIntentKind.multiCategoryReceipt,
        );
        expect(receipt.multiCategoryReceipt!.totalAmountMinor, 500000);
        expect(receipt.multiCategoryReceipt!.splitLines.length, 2);
        expect(
          receipt.multiCategoryReceipt!.splitLines[0].categoryName,
          'Ăn uống',
        );
        expect(
          receipt.multiCategoryReceipt!.splitLines[1].categoryName,
          'Việc nhà & Gia dụng',
        );

        final batch = VoiceFinancialNlpEngine.analyze(
          'Sáng ăn phở 65 nghìn đổ xăng 90 nghìn chiều nhận lương mười tám triệu rưỡi',
        );
        expect(batch, isNotNull);
        expect(batch!.intentKind, VoiceSentenceIntentKind.batchTransactions);
        expect(batch.personalEntries.length, 3);
        expect(batch.personalEntries[0].amountMinor, 65000);
        expect(batch.personalEntries[1].amountMinor, 90000);
        expect(batch.personalEntries[2].amountMinor, 18500000);
        expect(batch.personalEntries[2].kind, TransactionKind.income);
      },
    );

    test(
      'Zero-Touch Auto-Confirm updates wallet balance automatically without manual approval',
      () async {
        final mockAuth = MockFirebaseAuth();
        final fakeFirestore = FakeFirebaseFirestore();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
        );

        final signUp = await sl<AuthRepository>().signUp(
          email: 'zero@lifeos.vn',
          password: 'Password123!',
          fullName: 'Zero Touch',
        );
        final user = (signUp as Success<UserEntity>).value;
        final notifRepo = sl<NotificationsRepository>();
        final txRepo = sl<TransactionRepository>();

        await notifRepo.updateAndroidNotificationConsent(
          userId: user.id,
          enabled: true,
          allowedPackages: const ['com.VCB'],
          autoConfirmSignals: true,
        );

        await notifRepo.ingestAndroidNotification(
          userId: user.id,
          defaultWalletId: 'wallet_bank_default',
          packageName: 'com.VCB',
          title: 'VCB Digibank',
          body: 'TK 0071***88 GD: +5.000.000VND. ND: Thuong du an thang 11',
        );

        final wallets =
            (await txRepo.watchWallets(user.id).first
                    as Success<List<WalletEntity>>)
                .value;
        final bank = wallets.firstWhere((w) => w.id == 'wallet_bank_default');
        expect(bank.balanceMinor, 5000000);
      },
    );
  });
}
