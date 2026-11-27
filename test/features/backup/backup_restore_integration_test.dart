import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:life_os/core/backup/lifeos_backup_restore_engine.dart';
import 'package:life_os/core/di/backup_dependencies.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/features/backup/data/datasources/firestore_backup_remote_datasource.dart';
import 'package:life_os/features/backup/data/repositories/backup_repository_impl.dart';
import 'package:life_os/features/backup/domain/entities/backup_entities.dart';
import 'package:life_os/features/backup/domain/repositories/backup_repository.dart';
import 'package:life_os/features/backup/presentation/bloc/backup_bloc.dart';
import 'package:life_os/features/budgets/data/repositories/budget_repository_impl.dart';
import 'package:life_os/features/calendar/data/repositories/calendar_repository_impl.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/daily_life/data/repositories/daily_life_repository_impl.dart';
import 'package:life_os/features/daily_life/domain/entities/daily_life_entities.dart';
import 'package:life_os/features/tasks/data/repositories/task_repository_impl.dart';
import 'package:life_os/features/tasks/domain/entities/task_entities.dart';
import 'package:life_os/features/transactions/data/datasources/transaction_remote_datasource.dart';
import 'package:life_os/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:life_os/features/vehicles/data/repositories/vehicle_repository_impl.dart';
import 'package:life_os/features/vehicles/domain/entities/vehicle_entities.dart';

Future<
  ({
    int bankBalanceMinor,
    int cardBalanceMinor,
    int totalTxCount,
    String bankWalletId,
    String cardWalletId,
  })
>
_seedRichOwnerAccount({
  required FakeFirebaseFirestore db,
  required String userId,
}) async {
  final txDs = TransactionRemoteDataSource(db);
  final txRepo = TransactionRepositoryImpl(txDs);

  // 2 wallets: bank + credit card
  final bankWallet =
      (await txRepo.createWallet(
                userId: userId,
                name: 'VCB Tài khoản chính',
                type: WalletType.bank,
                openingBalanceMinor: 60000000,
                bankCode: 'VCB',
                maskedAccount: '•••• 1234',
              )
              as Success<WalletEntity>)
          .value;

  final cardWallet =
      (await txRepo.createWallet(
                userId: userId,
                name: 'Thẻ tín dụng Techcombank',
                type: WalletType.creditCard,
                openingBalanceMinor: -4000000,
                bankCode: 'TCB',
                maskedAccount: '•••• 9876',
              )
              as Success<WalletEntity>)
          .value;

  // Category
  await db
      .collection('users')
      .doc(userId)
      .collection('categories')
      .doc('cat_food')
      .set({
        'id': 'cat_food',
        'ownerId': userId,
        'name': 'Ăn uống',
        'direction': 'debit',
        'iconKey': 'restaurant',
      });

  // Month 1 (2026-10): >100 transactions within ONE month (112 expenses + 2 incomes)
  for (var i = 1; i <= 112; i++) {
    final day = ((i - 1) % 28) + 1;
    await txRepo.createTransaction(
      operationId: 'tx_m1_exp_$i',
      userId: userId,
      walletId: i.isEven ? cardWallet.id : bankWallet.id,
      categoryName: i % 3 == 0 ? 'Di chuyển' : 'Ăn uống',
      kind: TransactionKind.expense,
      amountMinor: 15000 + (i * 1000),
      merchant: 'Cửa hàng #$i',
      note: 'Chi tiêu tháng 10 #$i',
      occurredAt: DateTime(2026, 10, day, 9, i % 60),
    );
  }
  await txRepo.createTransaction(
    operationId: 'tx_m1_inc_1',
    userId: userId,
    walletId: bankWallet.id,
    categoryName: 'Lương',
    kind: TransactionKind.income,
    amountMinor: 25000000,
    merchant: 'Công ty LifeOS',
    occurredAt: DateTime(2026, 10, 5, 10, 0),
  );
  await txRepo.createTransaction(
    operationId: 'tx_m1_inc_2',
    userId: userId,
    walletId: bankWallet.id,
    categoryName: 'Thưởng',
    kind: TransactionKind.income,
    amountMinor: 3500000,
    merchant: 'Thưởng dự án',
    occurredAt: DateTime(2026, 10, 20, 14, 0),
  );

  // Month 2 (2026-11): transfer, creditCardPayment, reversal, split expense, provisional tx
  await txRepo.createTransaction(
    operationId: 'tx_m2_transfer_1',
    userId: userId,
    walletId: bankWallet.id,
    targetWalletId: cardWallet.id,
    categoryName: 'Chuyển nội bộ',
    kind: TransactionKind.transfer,
    amountMinor: 1200000,
    merchant: 'Nạp sang thẻ',
    occurredAt: DateTime(2026, 11, 2, 11, 0),
  );

  await txRepo.createTransaction(
    operationId: 'tx_m2_cc_pay_1',
    userId: userId,
    walletId: bankWallet.id,
    targetWalletId: cardWallet.id,
    categoryName: 'Trả nợ thẻ tín dụng',
    kind: TransactionKind.creditCardPayment,
    amountMinor: 2800000,
    merchant: 'Thanh toán sao kê TCB',
    occurredAt: DateTime(2026, 11, 8, 16, 30),
  );

  await txRepo.createTransaction(
    operationId: 'tx_m2_exp_to_rev',
    userId: userId,
    walletId: bankWallet.id,
    categoryName: 'Mua sắm',
    kind: TransactionKind.expense,
    amountMinor: 450000,
    merchant: 'Đơn hàng hủy',
    occurredAt: DateTime(2026, 11, 10, 12, 0),
  );
  await txRepo.reverseTransaction(
    userId: userId,
    transactionId: 'tx_m2_exp_to_rev',
    reason: 'Shop hoàn tiền toàn bộ',
  );

  // Also test reversing a transfer (must restore both source & destination balances!)
  await txRepo.createTransaction(
    operationId: 'tx_m2_tr_to_rev',
    userId: userId,
    walletId: bankWallet.id,
    targetWalletId: cardWallet.id,
    categoryName: 'Chuyển nội bộ',
    kind: TransactionKind.transfer,
    amountMinor: 300000,
    merchant: 'Chuyển nhầm ví',
    occurredAt: DateTime(2026, 11, 12, 12, 0),
  );
  await txRepo.reverseTransaction(
    userId: userId,
    transactionId: 'tx_m2_tr_to_rev',
    reason: 'Hoàn tác chuyển nhầm ví',
  );

  // Split transaction in month 2
  await txRepo.createTransaction(
    operationId: 'tx_m2_split_1',
    userId: userId,
    walletId: bankWallet.id,
    categoryName: 'Siêu thị',
    kind: TransactionKind.expense,
    amountMinor: 500000,
    merchant: 'Co.opmart',
    occurredAt: DateTime(2026, 11, 15, 18, 0),
    splitLines: const [
      TransactionSplitLine(categoryName: 'Ăn uống', amountMinor: 320000),
      TransactionSplitLine(categoryName: 'Gia dụng', amountMinor: 180000),
    ],
  );

  // Provisional transaction (must NOT mutate wallet balance!)
  await db
      .collection('users')
      .doc(userId)
      .collection('transactions')
      .doc('tx_m2_prov_1')
      .set({
        'id': 'tx_m2_prov_1',
        'operationId': 'tx_m2_prov_1',
        'ownerId': userId,
        'walletId': bankWallet.id,
        'categoryName': 'Chờ xác nhận',
        'kind': 'expense',
        'direction': 'debit',
        'amountMinor': 999000,
        'currencyCode': 'VND',
        'merchant': 'Thông báo ngân hàng nháp',
        'occurredAt': Timestamp.fromDate(DateTime(2026, 11, 18, 8, 0)),
        'monthKey': '2026-11',
        'sourceKind': 'androidNotification',
        'verification': 'provisional',
        'verificationStatus': 'PROVISIONAL',
        'ledgerApplied': false,
        'crossSourceFingerprint': 'fp_prov_1',
      });

  // Budgets across 2 months
  final budgetRepo = BudgetRepositoryImpl(BudgetRemoteDataSource(db));
  await budgetRepo.upsertBudget(
    userId: userId,
    categoryId: 'cat_food',
    categoryName: 'Ăn uống',
    monthKey: '2026-10',
    limitMinor: 5000000,
  );
  await budgetRepo.upsertBudget(
    userId: userId,
    categoryId: 'cat_food',
    categoryName: 'Ăn uống',
    monthKey: '2026-11',
    limitMinor: 6000000,
  );

  // Tasks
  final taskRepo = TaskRepositoryImpl(TaskRemoteDataSource(db));
  await taskRepo.createTask(
    createdBy: userId,
    creatorName: 'Minh',
    assigneeId: userId,
    assigneeName: 'Minh',
    title: 'Đóng tiền bảo hiểm xe',
    description: 'Gia hạn trước ngày 30',
    dueAt: DateTime(2026, 11, 28, 17, 0),
    priority: TaskPriorityLevel.high,
    recurrence: TaskRecurrence.none,
  );

  // Calendar + Private events
  final calDs = CalendarRemoteDataSource(db);
  final customCal = await calDs.createCalendar(
    userId: userId,
    summary: 'Lịch Công việc',
    colorHex: '#1565C0',
  );
  await calDs.createEvent(
    userId: userId,
    userName: 'Minh',
    calendarId: customCal.id,
    visibility: CalendarEventVisibility.privateEvent,
    title: 'Họp tổng kết năm',
    description: 'Phòng họp A2',
    startsAt: DateTime(2026, 11, 27, 9, 0),
    endsAt: DateTime(2026, 11, 27, 10, 30),
    publishBusySlot: false,
  );

  // Vehicle + maintenance + bill
  final vehDs = VehicleRemoteDataSource(db);
  await vehDs.createVehicle(
    userId: userId,
    isFamilyShared: false,
    name: 'Honda Vision',
    plateNumber: '59X1-555.88',
    currentOdometerKm: 14500,
    serviceIntervalKm: 2000,
    serviceIntervalDays: 90,
  );
  final vehList = await vehDs.watchVehicles(userId: userId).first;
  await vehDs.recordMaintenance(
    vehicle: vehList.first,
    serviceTitle: 'Thay nhớt định kỳ',
    odometerKm: 14500,
    costMinor: 0,
  );
  await vehDs.createRecurringBill(
    userId: userId,
    title: 'Tiền điện EVN',
    providerName: 'EVNHCMC',
    estimatedAmountMinor: 650000,
    nextDueDate: DateTime(2026, 12, 5),
  );

  // Notes
  final dailyRepo = DailyLifeRepositoryImpl(db);
  await dailyRepo.addOrUpdateNote(
    userId: userId,
    title: 'Ghi chú chuyển máy',
    content: 'Nhớ sao lưu đầy đủ trước khi gỡ ứng dụng cũ.',
    categoryTag: 'Quan trọng',
    mood: LifeMoodLevel.great,
    isPinned: true,
  );

  // Documents metadata (localAttachmentPath must NOT leak into JSON export)
  await db
      .collection('users')
      .doc(userId)
      .collection('documents')
      .doc('doc_cccd')
      .set({
        'id': 'doc_cccd',
        'ownerId': userId,
        'folder': 'identity',
        'title': 'CCCD gắn chip',
        'referenceCode': '079200012345',
        'note': 'Hết hạn 2035',
        'localAttachmentPath': '/data/user/0/vn.lifeos/vault/cccd.enc',
        'localAttachmentStorageKey': 'identity_abc_cccd.enc',
        'createdAt': '2026-10-01T00:00:00Z',
      });

  final finalWallets =
      (await txRepo.fetchAllWalletsPaginated(userId: userId, pageSize: 25)
              as Success<List<WalletEntity>>)
          .value;
  final finalTxs =
      (await txRepo.fetchAllTransactionsPaginated(userId: userId, pageSize: 25)
              as Success<List<TransactionEntity>>)
          .value;

  final bankFinal = finalWallets.firstWhere((w) => w.id == bankWallet.id);
  final cardFinal = finalWallets.firstWhere((w) => w.id == cardWallet.id);

  // 112 expenses + 2 incomes + 1 transfer + 1 ccPayment + 1 exp + 1 rev + 1 split + 1 provisional = 120
  return (
    bankBalanceMinor: bankFinal.balanceMinor,
    cardBalanceMinor: cardFinal.balanceMinor,
    totalTxCount: finalTxs.length,
    bankWalletId: bankWallet.id,
    cardWalletId: cardWallet.id,
  );
}

void main() {
  group('Backup & Restore Full Integrity Integration (FakeFirebaseFirestore)', () {
    late FakeFirebaseFirestore db;

    setUp(() async {
      db = FakeFirebaseFirestore();
      await GetIt.instance.reset();
    });

    tearDown(() async {
      await GetIt.instance.reset();
    });

    test(
      'registerBackupDependencies wires BackupRepository and BackupBloc cleanly',
      () {
        final sl = GetIt.instance;
        sl.registerSingleton<FirebaseFirestore>(db);
        registerBackupDependencies(sl);

        expect(sl.isRegistered<BackupRepository>(), isTrue);
        expect(sl.isRegistered<BackupBloc>(), isTrue);
        final bloc = sl<BackupBloc>();
        expect(bloc, isA<BackupBloc>());
        bloc.close();
      },
    );

    test(
      'exports ALL multi-month >100 txs + all kinds + all collections & restores to clean account with exact per-wallet balances',
      () async {
        const srcUser = 'u_source_full';
        const dstUser = 'u_clean_install';

        final seeded = await _seedRichOwnerAccount(db: db, userId: srcUser);
        expect(seeded.totalTxCount, 122);

        final txRepo = TransactionRepositoryImpl(
          TransactionRemoteDataSource(db),
        );
        final backupDs = FirestoreBackupRemoteDataSource(
          firestore: db,
          transactionRepository: txRepo,
          createTransactionUseCase: CreateTransactionUseCase(txRepo),
          reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
          pageSize: 25, // Force 5+ cursor pages!
        );
        final backupRepo = BackupRepositoryImpl(remoteDataSource: backupDs);

        // 1. Export encrypted full backup
        final exportRes = await backupRepo.exportOwnerData(
          ownerId: srcUser,
          passphrase: 'MigrateKey#2026',
        );
        expect(exportRes.isSuccess, isTrue);
        final bundle = (exportRes as Success<BackupExportBundle>).value;
        expect(bundle.summary.walletCount, 2);
        expect(bundle.summary.transactionCount, 122);
        expect(bundle.summary.budgetCount, 2);
        expect(bundle.summary.taskCount, 1);
        expect(bundle.summary.eventCount, 1);
        expect(bundle.summary.vehicleCount, 1);
        expect(bundle.summary.noteCount, 1);

        // Verify CSV export ALSO has all 122 transactions (no 100 cap, no month filter)
        final csvRes = await backupRepo.exportTransactionsCsv(ownerId: srcUser);
        expect(csvRes.isSuccess, isTrue);
        final csvLines = (csvRes as Success<BackupExportBundle>)
            .value
            .archiveContent
            .trim()
            .split('\n');
        expect(csvLines.length, 123); // header + 122 rows

        // 2. Preview & verify archive
        final previewRes = await backupRepo.previewAndValidateArchive(
          rawArchiveText: bundle.archiveContent,
          passphrase: 'MigrateKey#2026',
        );
        expect(previewRes.isSuccess, isTrue);
        final preview = (previewRes as Success<BackupArchivePreview>).value;
        expect(preview.checksumVerified, isTrue);
        expect(preview.wasEncrypted, isTrue);
        expect(preview.transactionCount, 122);
        // Ensure localAttachmentPath was omitted from document metadata
        final exportedDoc =
            preview.collections[BackupCollectionCatalog.documents]!.single;
        expect(exportedDoc.containsKey('localAttachmentPath'), isFalse);
        expect(exportedDoc['localAttachmentOmitted'], isTrue);

        // 3. Restore into a completely clean account (0 wallets initially!)
        final restoreRes = await backupRepo.restoreOwnerData(
          targetUserId: dstUser,
          preview: preview,
          mode: BackupRestoreMode.merge,
          explicitReplaceConfirmation: false,
        );
        expect(restoreRes.isSuccess, isTrue);
        final report =
            (restoreRes as Success<BackupRestoreExecutionReport>).value;

        expect(report.isCleanSuccess, isTrue);
        expect(report.hasBalanceMismatches, isFalse);
        expect(report.failedCount, 0);
        expect(report.committedCount, preview.totalRecordCount);
        expect(report.walletBalanceChecks.length, 2);
        expect(report.walletBalanceChecks.every((c) => c.matched), isTrue);

        // 4. Verify restored Firestore data directly & via domain repositories
        final dstWallets =
            (await txRepo.fetchAllWalletsPaginated(
                      userId: dstUser,
                      pageSize: 25,
                    )
                    as Success<List<WalletEntity>>)
                .value;
        expect(dstWallets.length, 2);
        final dstBank = dstWallets.firstWhere(
          (w) => w.id == seeded.bankWalletId,
        );
        final dstCard = dstWallets.firstWhere(
          (w) => w.id == seeded.cardWalletId,
        );
        expect(dstBank.balanceMinor, seeded.bankBalanceMinor);
        expect(dstCard.balanceMinor, seeded.cardBalanceMinor);

        final dstTxs =
            (await txRepo.fetchAllTransactionsPaginated(
                      userId: dstUser,
                      pageSize: 25,
                    )
                    as Success<List<TransactionEntity>>)
                .value;
        expect(dstTxs.length, 122);

        final transferTx = dstTxs.firstWhere((t) => t.id == 'tx_m2_transfer_1');
        expect(transferTx.kind, TransactionKind.transfer);
        expect(transferTx.walletId, seeded.bankWalletId);
        expect(transferTx.targetWalletId, seeded.cardWalletId);

        final ccTx = dstTxs.firstWhere((t) => t.id == 'tx_m2_cc_pay_1');
        expect(ccTx.kind, TransactionKind.creditCardPayment);
        expect(ccTx.walletId, seeded.bankWalletId);
        expect(ccTx.targetWalletId, seeded.cardWalletId);

        final revTx = dstTxs.firstWhere((t) => t.id == 'rev_tx_m2_exp_to_rev');
        expect(revTx.kind, TransactionKind.reversal);
        expect(revTx.reversalOfId, 'tx_m2_exp_to_rev');

        final origReversedTx = dstTxs.firstWhere(
          (t) => t.id == 'tx_m2_exp_to_rev',
        );
        expect(origReversedTx.isReversed, isTrue);

        final revTrTx = dstTxs.firstWhere((t) => t.id == 'rev_tx_m2_tr_to_rev');
        expect(revTrTx.kind, TransactionKind.reversal);
        expect(revTrTx.reversalOfId, 'tx_m2_tr_to_rev');
        expect(revTrTx.targetWalletId, seeded.cardWalletId);

        final provTx = dstTxs.firstWhere((t) => t.id == 'tx_m2_prov_1');
        expect(provTx.verification, TransactionVerification.provisional);
        expect(provTx.ledgerApplied, isFalse);

        final splitTx = dstTxs.firstWhere((t) => t.id == 'tx_m2_split_1');
        expect(splitTx.splitLines.length, 2);

        // Verify budgets, tasks, calendar events, vehicles, notes via feature repositories
        final dstOctBudgets =
            (await BudgetRepositoryImpl(
                      BudgetRemoteDataSource(db),
                    ).watchBudgets(userId: dstUser, monthKey: '2026-10').first
                    as Success)
                .value;
        expect(dstOctBudgets.length, 1);

        final dstTasks =
            (await TaskRepositoryImpl(
                      TaskRemoteDataSource(db),
                    ).watchTasks(userId: dstUser).first
                    as Success<List<TaskEntity>>)
                .value;
        expect(dstTasks.length, 1);
        expect(dstTasks.single.title, 'Đóng tiền bảo hiểm xe');

        final dstEvents =
            (await CalendarRepositoryImpl(
                      CalendarRemoteDataSource(db),
                    ).watchEvents(userId: dstUser).first
                    as Success<List<CalendarEventEntity>>)
                .value;
        expect(dstEvents.length, 1);
        expect(dstEvents.single.title, 'Họp tổng kết năm');
        expect(dstEvents.single.startsAt.year, 2026);
        expect(dstEvents.single.startsAt.month, 11);
        expect(dstEvents.single.startsAt.day, 27);

        final dstVehicles =
            (await VehicleRepositoryImpl(
                      VehicleRemoteDataSource(db),
                    ).watchVehicles(userId: dstUser).first
                    as Success<List<VehicleEntity>>)
                .value;
        expect(dstVehicles.length, 1);
        expect(dstVehicles.single.name, 'Honda Vision');

        final dstMaint =
            (await VehicleRepositoryImpl(
                      VehicleRemoteDataSource(db),
                    ).watchMaintenanceHistory(vehicle: dstVehicles.single).first
                    as Success<List<MaintenanceRecordEntity>>)
                .value;
        expect(dstMaint.length, 1);

        final dstDaily = await DailyLifeRepositoryImpl(
          db,
        ).watchAll(userId: dstUser).firstWhere((s) => s.notes.isNotEmpty);
        expect(dstDaily.notes.length, 1);
        expect(dstDaily.notes.single.title, 'Ghi chú chuyển máy');
      },
    );

    test(
      'interrupt mid-import after N writes then retry -> no duplicates and per-wallet balances exact',
      () async {
        const srcUser = 'u_src_interrupt';
        const dstUser = 'u_dst_resumable';

        final seeded = await _seedRichOwnerAccount(db: db, userId: srcUser);
        final txRepo = TransactionRepositoryImpl(
          TransactionRemoteDataSource(db),
        );

        final cleanDs = FirestoreBackupRemoteDataSource(
          firestore: db,
          transactionRepository: txRepo,
          createTransactionUseCase: CreateTransactionUseCase(txRepo),
          reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
          pageSize: 25,
        );
        final cleanRepo = BackupRepositoryImpl(remoteDataSource: cleanDs);
        final exportRes = await cleanRepo.exportOwnerData(
          ownerId: srcUser,
          passphrase: 'InterruptPass#2026',
        );
        final bundle = (exportRes as Success<BackupExportBundle>).value;
        final preview =
            (await cleanRepo.previewAndValidateArchive(
                      rawArchiveText: bundle.archiveContent,
                      passphrase: 'InterruptPass#2026',
                    )
                    as Success<BackupArchivePreview>)
                .value;

        // Run 1: Fail at write #65 (after 2 wallets + 62 transactions committed = 64 writes)
        const failAtWrite = 65;
        final failingDs = FirestoreBackupRemoteDataSource(
          firestore: db,
          transactionRepository: txRepo,
          createTransactionUseCase: CreateTransactionUseCase(txRepo),
          reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
          pageSize: 25,
          onBeforeWrite: (col, id, writeIndex) async {
            if (writeIndex == failAtWrite) {
              throw FirebaseException(
                plugin: 'cloud_firestore',
                code: 'unavailable',
                message: 'Mất kết nối mạng tạm thời giữa chừng',
              );
            }
          },
        );
        final failingRepo = BackupRepositoryImpl(remoteDataSource: failingDs);

        final partialRes = await failingRepo.restoreOwnerData(
          targetUserId: dstUser,
          preview: preview,
          mode: BackupRestoreMode.merge,
          explicitReplaceConfirmation: false,
        );
        expect(partialRes.isSuccess, isTrue);
        final partialReport =
            (partialRes as Success<BackupRestoreExecutionReport>).value;

        // Must accurately report 64 committed writes, partial failure, and balance mismatch!
        expect(partialReport.committedCount, 64);
        expect(partialReport.isPartialFailure, isTrue);
        expect(partialReport.isCleanSuccess, isFalse);
        expect(partialReport.hasBalanceMismatches, isTrue);

        // Run 2: Retry same archive into same user without network fault
        final retryRes = await cleanRepo.restoreOwnerData(
          targetUserId: dstUser,
          preview: preview,
          mode: BackupRestoreMode.merge,
          explicitReplaceConfirmation: false,
        );
        expect(retryRes.isSuccess, isTrue);
        final retryReport =
            (retryRes as Success<BackupRestoreExecutionReport>).value;

        expect(retryReport.isCleanSuccess, isTrue);
        expect(retryReport.hasBalanceMismatches, isFalse);
        expect(retryReport.failedCount, 0);
        expect(retryReport.skippedCount, 64);
        expect(retryReport.committedCount, preview.totalRecordCount - 64);

        // Verify zero duplicates & exact per-wallet balances
        final dstWallets =
            (await txRepo.fetchAllWalletsPaginated(
                      userId: dstUser,
                      pageSize: 25,
                    )
                    as Success<List<WalletEntity>>)
                .value;
        expect(dstWallets.length, 2);
        expect(
          dstWallets
              .firstWhere((w) => w.id == seeded.bankWalletId)
              .balanceMinor,
          seeded.bankBalanceMinor,
        );
        expect(
          dstWallets
              .firstWhere((w) => w.id == seeded.cardWalletId)
              .balanceMinor,
          seeded.cardBalanceMinor,
        );

        final dstTxs =
            (await txRepo.fetchAllTransactionsPaginated(
                      userId: dstUser,
                      pageSize: 25,
                    )
                    as Success<List<TransactionEntity>>)
                .value;
        expect(dstTxs.length, 122);

        // Run 3: Re-running complete merge again is 100% idempotent (0 committed, all skipped)
        final thirdRes = await cleanRepo.restoreOwnerData(
          targetUserId: dstUser,
          preview: preview,
          mode: BackupRestoreMode.merge,
          explicitReplaceConfirmation: false,
        );
        final thirdReport =
            (thirdRes as Success<BackupRestoreExecutionReport>).value;
        expect(thirdReport.committedCount, 0);
        expect(thirdReport.skippedCount, preview.totalRecordCount);
        expect(thirdReport.isCleanSuccess, isTrue);
      },
    );

    test(
      'fresh install with legacy archive missing wallets list auto-creates missing wallet safely',
      () async {
        const dstUser = 'u_fresh_legacy';
        final txRepo = TransactionRepositoryImpl(
          TransactionRemoteDataSource(db),
        );
        final backupDs = FirestoreBackupRemoteDataSource(
          firestore: db,
          transactionRepository: txRepo,
          createTransactionUseCase: CreateTransactionUseCase(txRepo),
          reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
        );
        final backupRepo = BackupRepositoryImpl(remoteDataSource: backupDs);

        final legacyPreview = BackupArchivePreview(
          schemaVersion: 2,
          ownerId: 'u_old',
          exportedAt: DateTime.utc(2026, 11, 1),
          checksumVerified: true,
          wasEncrypted: false,
          archiveSha256: 'abc12345',
          collections: const {
            BackupCollectionCatalog.wallets: [],
            BackupCollectionCatalog.transactions: [
              {
                'id': 'tx_legacy_inc',
                'walletId': 'wallet_cash_default',
                'kind': 'income',
                'amountMinor': 2000000,
                'categoryName': 'Thu nhập',
                'merchant': 'Tiền mặt',
                'occurredAt': '2026-11-01T08:00:00Z',
              },
              {
                'id': 'tx_legacy_exp',
                'walletId': 'wallet_cash_default',
                'kind': 'expense',
                'amountMinor': 350000,
                'categoryName': 'Ăn uống',
                'merchant': 'Quán ăn',
                'occurredAt': '2026-11-02T12:00:00Z',
              },
            ],
          },
        );

        final res = await backupRepo.restoreOwnerData(
          targetUserId: dstUser,
          preview: legacyPreview,
          mode: BackupRestoreMode.merge,
          explicitReplaceConfirmation: false,
        );
        expect(res.isSuccess, isTrue);
        final report = (res as Success<BackupRestoreExecutionReport>).value;
        expect(report.failedCount, 0);

        final wallets =
            (await txRepo.fetchAllWalletsPaginated(userId: dstUser)
                    as Success<List<WalletEntity>>)
                .value;
        expect(wallets.length, 1);
        expect(wallets.single.id, 'wallet_cash_default');
        expect(wallets.single.balanceMinor, 1650000);
      },
    );

    test(
      'reports balance mismatch honestly instead of claiming success when target wallet diverges',
      () async {
        const dstUser = 'u_mismatch';
        final txRepo = TransactionRepositoryImpl(
          TransactionRemoteDataSource(db),
        );
        // Existing wallet already has divergent 9,000,000 VND
        await db
            .collection('users')
            .doc(dstUser)
            .collection('wallets')
            .doc('w_main')
            .set({
              'id': 'w_main',
              'ownerId': dstUser,
              'name': 'Ví chính',
              'type': 'bank',
              'balanceMinor': 9000000,
              'isEstimatedBalance': true,
            });

        final backupDs = FirestoreBackupRemoteDataSource(
          firestore: db,
          transactionRepository: txRepo,
          createTransactionUseCase: CreateTransactionUseCase(txRepo),
          reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
        );
        final backupRepo = BackupRepositoryImpl(remoteDataSource: backupDs);

        final preview = BackupArchivePreview(
          schemaVersion: 3,
          ownerId: 'u_other',
          exportedAt: DateTime.utc(2026, 11, 20),
          checksumVerified: true,
          wasEncrypted: false,
          archiveSha256: 'deadbeef',
          collections: const {
            BackupCollectionCatalog.wallets: [
              {
                'id': 'w_main',
                'name': 'Ví chính',
                'type': 'bank',
                'balanceMinor': 3000000,
              },
            ],
            BackupCollectionCatalog.transactions: [
              {
                'id': 'tx_new_1',
                'walletId': 'w_main',
                'kind': 'expense',
                'amountMinor': 200000,
                'categoryName': 'Ăn uống',
                'merchant': 'Bún chả',
                'occurredAt': '2026-11-20T05:00:00Z',
              },
            ],
          },
        );

        final res = await backupRepo.restoreOwnerData(
          targetUserId: dstUser,
          preview: preview,
          mode: BackupRestoreMode.merge,
          explicitReplaceConfirmation: false,
        );
        expect(res.isSuccess, isTrue);
        final report = (res as Success<BackupRestoreExecutionReport>).value;
        expect(report.hasBalanceMismatches, isTrue);
        expect(report.isCleanSuccess, isFalse);
        expect(report.walletBalanceChecks.single.matched, isFalse);
        expect(report.walletBalanceChecks.single.expectedBalanceMinor, 3000000);
        expect(report.walletBalanceChecks.single.actualBalanceMinor, 8800000);
        expect(
          report.detailsVi.any((line) => line.contains('Lệch ví')),
          isTrue,
        );
      },
    );

    test(
      'supports importAsNew wallet/tx remapping & replaceConfirmed explicit confirmation guard',
      () async {
        const srcUser = 'u_src_modes';
        const dstUser = 'u_dst_modes';
        final txRepo = TransactionRepositoryImpl(
          TransactionRemoteDataSource(db),
        );
        final backupDs = FirestoreBackupRemoteDataSource(
          firestore: db,
          transactionRepository: txRepo,
          createTransactionUseCase: CreateTransactionUseCase(txRepo),
          reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
        );
        final backupRepo = BackupRepositoryImpl(remoteDataSource: backupDs);

        final w1 =
            (await txRepo.createWallet(
                      userId: srcUser,
                      name: 'Ví gốc',
                      type: WalletType.cash,
                      openingBalanceMinor: 1000000,
                    )
                    as Success<WalletEntity>)
                .value;
        await txRepo.createTransaction(
          operationId: 'tx_orig_1',
          userId: srcUser,
          walletId: w1.id,
          categoryName: 'Ăn uống',
          kind: TransactionKind.expense,
          amountMinor: 100000,
          merchant: 'Bánh mì',
          occurredAt: DateTime(2026, 11, 20),
        );

        final bundle =
            (await backupRepo.exportOwnerData(
                      ownerId: srcUser,
                      passphrase: 'ModesPass#2026',
                    )
                    as Success<BackupExportBundle>)
                .value;
        final preview =
            (await backupRepo.previewAndValidateArchive(
                      rawArchiveText: bundle.archiveContent,
                      passphrase: 'ModesPass#2026',
                    )
                    as Success<BackupArchivePreview>)
                .value;

        // Guard check on replaceConfirmed without confirmation
        final blockedReplace = await backupRepo.restoreOwnerData(
          targetUserId: dstUser,
          preview: preview,
          mode: BackupRestoreMode.replaceConfirmed,
          explicitReplaceConfirmation: false,
        );
        expect(blockedReplace, isA<Err<BackupRestoreExecutionReport>>());

        // Pre-seed dstUser with same wallet ID `w1.id` and balance 5,000,000
        await db
            .collection('users')
            .doc(dstUser)
            .collection('wallets')
            .doc(w1.id)
            .set({
              'id': w1.id,
              'ownerId': dstUser,
              'name': 'Ví hiện tại',
              'type': 'cash',
              'balanceMinor': 5000000,
              'isEstimatedBalance': true,
            });

        // importAsNew creates non-colliding remapped wallet & preserves existing 5,000,000 wallet
        final importAsNewRes = await backupRepo.restoreOwnerData(
          targetUserId: dstUser,
          preview: preview,
          mode: BackupRestoreMode.importAsNew,
          explicitReplaceConfirmation: false,
        );
        final importReport =
            (importAsNewRes as Success<BackupRestoreExecutionReport>).value;
        expect(importReport.isCleanSuccess, isTrue);

        final dstWallets =
            (await txRepo.fetchAllWalletsPaginated(userId: dstUser)
                    as Success<List<WalletEntity>>)
                .value;
        expect(dstWallets.length, 2);
        expect(
          dstWallets.firstWhere((w) => w.id == w1.id).balanceMinor,
          5000000,
        );
        final importedWallet = dstWallets.firstWhere((w) => w.id != w1.id);
        expect(importedWallet.balanceMinor, 900000);
      },
    );
  });
}
