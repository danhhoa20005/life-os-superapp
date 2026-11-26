import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/di/backup_dependencies.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/widgets/backup_restore_studio_sheet.dart';
import 'package:life_os/core/widgets/lifeos_design_system.dart';
import 'package:life_os/features/backup/data/datasources/firestore_backup_remote_datasource.dart';
import 'package:life_os/features/backup/data/repositories/backup_repository_impl.dart';
import 'package:life_os/features/backup/data/services/backup_file_share_service_impl.dart';
import 'package:life_os/features/backup/domain/entities/backup_entities.dart';
import 'package:life_os/features/backup/domain/repositories/backup_file_share_service.dart';
import 'package:life_os/features/backup/domain/repositories/backup_repository.dart';
import 'package:life_os/features/backup/domain/usecases/backup_usecases.dart';
import 'package:life_os/features/backup/presentation/bloc/backup_bloc.dart';
import 'package:life_os/features/calendar/data/repositories/calendar_repository_impl.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/daily_life/data/repositories/daily_life_repository_impl.dart';
import 'package:life_os/features/transactions/data/datasources/transaction_remote_datasource.dart';
import 'package:life_os/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/domain/usecases/transaction_usecases.dart';

Widget _wrapApp(Widget child, {bool dark = false, double textScale = 1.0}) {
  return MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    builder: (ctx, inner) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)),
      child: LifeOsTopToastHost(child: inner!),
    ),
    home: child,
  );
}

Future<void> _seedSmallRichData(FakeFirebaseFirestore db, String userId) async {
  final txRepo = TransactionRepositoryImpl(TransactionRemoteDataSource(db));
  final wBank =
      (await txRepo.createWallet(
                userId: userId,
                name: 'VCB Chính',
                type: WalletType.bank,
                openingBalanceMinor: 10000000,
              )
              as Success<WalletEntity>)
          .value;
  final wCard =
      (await txRepo.createWallet(
                userId: userId,
                name: 'Thẻ Tín Dụng',
                type: WalletType.creditCard,
                openingBalanceMinor: -1000000,
              )
              as Success<WalletEntity>)
          .value;

  for (var i = 1; i <= 105; i++) {
    await txRepo.createTransaction(
      operationId: 'tx_m1_$i',
      userId: userId,
      walletId: wBank.id,
      categoryName: 'Ăn uống',
      kind: TransactionKind.expense,
      amountMinor: 25000,
      merchant: 'Quán #$i',
      occurredAt: DateTime(2026, 10, (i % 28) + 1, 9, 0),
    );
  }
  await txRepo.createTransaction(
    operationId: 'tx_m2_tr',
    userId: userId,
    walletId: wBank.id,
    targetWalletId: wCard.id,
    categoryName: 'Chuyển nội bộ',
    kind: TransactionKind.transfer,
    amountMinor: 500000,
    merchant: 'Chuyển sang thẻ',
    occurredAt: DateTime(2026, 11, 5, 10, 0),
  );
  await txRepo.createTransaction(
    operationId: 'tx_m2_cc',
    userId: userId,
    walletId: wBank.id,
    targetWalletId: wCard.id,
    categoryName: 'Trả thẻ',
    kind: TransactionKind.creditCardPayment,
    amountMinor: 500000,
    merchant: 'Thanh toán thẻ',
    occurredAt: DateTime(2026, 11, 10, 14, 0),
  );
  await txRepo.createTransaction(
    operationId: 'tx_m2_rev_base',
    userId: userId,
    walletId: wBank.id,
    categoryName: 'Mua sắm',
    kind: TransactionKind.expense,
    amountMinor: 120000,
    merchant: 'Đơn hoàn',
    occurredAt: DateTime(2026, 11, 12, 11, 0),
  );
  await txRepo.reverseTransaction(
    userId: userId,
    transactionId: 'tx_m2_rev_base',
    reason: 'Hoàn đơn hàng',
  );

  await CalendarRemoteDataSource(db).createEvent(
    userId: userId,
    userName: 'Minh',
    visibility: CalendarEventVisibility.privateEvent,
    title: 'Lịch hẹn bác sĩ',
    startsAt: DateTime(2026, 11, 26, 9, 0),
    endsAt: DateTime(2026, 11, 26, 10, 0),
    publishBusySlot: false,
  );

  await DailyLifeRepositoryImpl(db).addOrUpdateNote(
    userId: userId,
    title: 'Ghi chú quan trọng',
    content: 'Kiểm tra sao lưu định kỳ',
    categoryTag: 'Cá nhân',
  );
}

void main() {
  const updaterChannel = MethodChannel('vn.lifeos.app/app_updater');

  group('BackupRestoreStudioSheet Widget Tests (Finding 4 & Finding 6)', () {
    late FakeFirebaseFirestore db;
    late String clipboardValue;
    late int clipboardSetCalls;
    late List<MethodCall> shareCalls;

    setUp(() async {
      db = FakeFirebaseFirestore();
      await GetIt.instance.reset();
      clipboardValue = 'SENTINEL_CLIPBOARD_TOKEN_9911';
      clipboardSetCalls = 0;
      shareCalls = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardSetCalls++;
              final args = call.arguments as Map?;
              clipboardValue = (args?['text'] ?? '').toString();
              return null;
            }
            if (call.method == 'Clipboard.getData') {
              return <String, dynamic>{'text': clipboardValue};
            }
            return null;
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(updaterChannel, null);
      await GetIt.instance.reset();
    });

    testWidgets(
      'Finding 6: CSV & JSON export NEVER copy to clipboard when share succeeds or is cancelled',
      (tester) async {
        const userId = 'u_clip_guard';
        await _seedSmallRichData(db, userId);

        final sl = GetIt.instance;
        sl.registerSingleton<FirebaseFirestore>(db);
        registerBackupDependencies(sl);

        // Phase 1: Simulate Android native share sheet succeeding
        String? mockShareReturn = '/data/user/0/vn.lifeos/cache/exported.json';
        bool throwCancelException = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(updaterChannel, (call) async {
              if (call.method == 'shareTextFile') {
                shareCalls.add(call);
                if (throwCancelException) {
                  throw PlatformException(
                    code: 'CANCELLED',
                    message: 'User cancelled share sheet',
                  );
                }
                return mockShareReturn;
              }
              return null;
            });

        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          _wrapApp(
            Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: FilledButton(
                    key: const Key('open_sheet'),
                    onPressed: () => showLifeOsBackupRestoreSheet(
                      ctx,
                      userIdOverride: userId,
                    ),
                    child: const Text('Mở'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('open_sheet')));
        await tester.pumpAndSettle();

        // Confirm no Copy button on Export tab
        expect(find.textContaining('Sao chép'), findsNothing);

        // 1. Export JSON -> shares file, clipboard MUST keep sentinel!
        await tester.tap(find.byKey(const Key('backup_export_json_btn')));
        await tester.pumpAndSettle();
        expect(shareCalls.length, 1);
        expect(shareCalls.last.arguments['mimeType'], 'application/json');
        expect(clipboardSetCalls, 0);
        expect(
          (await Clipboard.getData(Clipboard.kTextPlain))?.text,
          'SENTINEL_CLIPBOARD_TOKEN_9911',
        );

        // Raw JSON preview is masked by PrivacyMaskFormatter until revealed
        expect(find.textContaining('••••••••••••••••••••'), findsOneWidget);
        expect(find.textContaining('Nhấn biểu tượng mắt'), findsOneWidget);
        await tester.tap(find.byKey(const Key('backup_toggle_raw_preview_btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('LIFEOS_BACKUP_V3'), findsOneWidget);

        // Dismiss toast
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        // 2. Export CSV -> shares file, clipboard MUST keep sentinel!
        await tester.tap(find.byKey(const Key('backup_export_csv_btn')));
        await tester.pumpAndSettle();
        expect(shareCalls.length, 2);
        expect(shareCalls.last.arguments['mimeType'], 'text/csv');
        expect(
          shareCalls.last.arguments['content'].toString(),
          contains('tx_m1_105'),
        );
        expect(clipboardSetCalls, 0);
        expect(
          (await Clipboard.getData(Clipboard.kTextPlain))?.text,
          'SENTINEL_CLIPBOARD_TOKEN_9911',
        );
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        // Phase 2: Simulate share cancelled (null return) -> sentinel preserved!
        mockShareReturn = null;
        await tester.tap(find.byKey(const Key('backup_export_json_btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Đã hủy chia sẻ tệp'), findsOneWidget);
        expect(clipboardSetCalls, 0);
        expect(
          (await Clipboard.getData(Clipboard.kTextPlain))?.text,
          'SENTINEL_CLIPBOARD_TOKEN_9911',
        );
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        // Phase 3: Simulate share cancelled via PlatformException -> sentinel preserved!
        throwCancelException = true;
        await tester.tap(find.byKey(const Key('backup_export_csv_btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Đã hủy chia sẻ tệp'), findsOneWidget);
        expect(clipboardSetCalls, 0);
        expect(
          (await Clipboard.getData(Clipboard.kTextPlain))?.text,
          'SENTINEL_CLIPBOARD_TOKEN_9911',
        );
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Finding 4 UI: shows full paginated count (>100), commits restore into clean account, and reports partial failures honestly at 360x800 @ 1.25x dark mode',
      (tester) async {
        const srcUser = 'u_ui_src';
        const dstUser = 'u_ui_dst';
        await _seedSmallRichData(db, srcUser);

        final tempExportDir = Directory(
          '${Directory.systemTemp.path}/lifeos_widget_test_exports_${DateTime.now().microsecondsSinceEpoch}',
        );
        addTearDown(() async {
          if (tempExportDir.existsSync()) {
            await tempExportDir.delete(recursive: true);
          }
        });

        final txRepo = TransactionRepositoryImpl(
          TransactionRemoteDataSource(db),
        );
        final backupDs = FirestoreBackupRemoteDataSource(
          firestore: db,
          transactionRepository: txRepo,
          createTransactionUseCase: CreateTransactionUseCase(txRepo),
          reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
          pageSize: 30,
        );
        final backupRepo = BackupRepositoryImpl(remoteDataSource: backupDs);
        final shareService = MethodChannelBackupFileShareService(
          fallbackDirectoryOverride: tempExportDir,
        );

        final sl = GetIt.instance;
        sl.registerSingleton<FirebaseFirestore>(db);
        sl.registerSingleton<BackupRepository>(backupRepo);
        sl.registerSingleton<BackupFileShareService>(shareService);
        registerBackupDependencies(sl);

        // Export archive from srcUser
        final exportRes = await backupRepo.exportOwnerData(ownerId: srcUser);
        final exportedArchive =
            (exportRes as Success<BackupExportBundle>).value.archiveContent;

        // Open sheet for dstUser (clean account with 0 wallets) on 360x800 @ 1.25x dark
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          _wrapApp(
            Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: FilledButton(
                    key: const Key('open_dst_sheet'),
                    onPressed: () => showLifeOsBackupRestoreSheet(
                      ctx,
                      userIdOverride: dstUser,
                    ),
                    child: const Text('Mở'),
                  ),
                ),
              ),
            ),
            dark: true,
            textScale: 1.25,
          ),
        );

        await tester.tap(find.byKey(const Key('open_dst_sheet')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Switch to Restore tab, paste payload, preview & commit
        await tester.tap(find.text('Khôi phục dữ liệu'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('backup_import_payload_field')),
          exportedArchive,
        );
        await tester.tap(find.byKey(const Key('backup_preview_validate_btn')));
        await tester.pumpAndSettle();

        final sheetList = find.byKey(
          const Key('backup_restore_sheet_list_view'),
        );
        await tester.drag(sheetList, const Offset(0, -320));
        await tester.pumpAndSettle();

        expect(find.text('Khớp toàn vẹn SHA-256'), findsOneWidget);
        expect(find.textContaining('Giao dịch: 109'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const Key('backup_apply_restore_btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('backup_apply_restore_btn')));
        await tester.pumpAndSettle();

        expect(find.text('Khôi phục hoàn tất'), findsOneWidget);
        expect(find.textContaining('Đã ghi thật: 113'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Expand Chi tiết on report card -> see per-wallet matched balance verification
        await tester.drag(sheetList, const Offset(0, -420));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('backup_report_details_toggle')),
        );
        await tester.pumpAndSettle();
        await tester.drag(sheetList, const Offset(0, -240));
        await tester.pumpAndSettle();
        expect(find.textContaining('VCB Chính'), findsOneWidget);
        expect(find.textContaining('(khớp)'), findsNWidgets(2));
        expect(tester.takeException(), isNull);

        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Finding 4 UI: displays exact partial failure count when mid-import fails instead of claiming success',
      (tester) async {
        const srcUser = 'u_ui_partial_src';
        const dstUser = 'u_ui_partial_dst';
        await _seedSmallRichData(db, srcUser);

        final txRepo = TransactionRepositoryImpl(
          TransactionRemoteDataSource(db),
        );
        final cleanDs = FirestoreBackupRemoteDataSource(
          firestore: db,
          transactionRepository: txRepo,
          createTransactionUseCase: CreateTransactionUseCase(txRepo),
          reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
        );
        final cleanRepo = BackupRepositoryImpl(remoteDataSource: cleanDs);
        final exportedArchive =
            (await cleanRepo.exportOwnerData(ownerId: srcUser)
                    as Success<BackupExportBundle>)
                .value
                .archiveContent;

        // Faulty datasource failing on write #10 (after 9 real commits)
        final faultyDs = FirestoreBackupRemoteDataSource(
          firestore: db,
          transactionRepository: txRepo,
          createTransactionUseCase: CreateTransactionUseCase(txRepo),
          reverseTransactionUseCase: ReverseTransactionUseCase(txRepo),
          onBeforeWrite: (_, _, idx) async {
            if (idx == 10) {
              throw FirebaseException(
                plugin: 'cloud_firestore',
                code: 'unavailable',
                message: 'Lỗi mạng giả lập',
              );
            }
          },
        );
        final faultyRepo = BackupRepositoryImpl(remoteDataSource: faultyDs);
        final bloc = BackupBloc(
          loadSummary: LoadBackupOwnerSummaryUseCase(faultyRepo),
          exportFullBackup: ExportFullBackupUseCase(faultyRepo),
          exportTransactionsCsv: ExportTransactionsCsvUseCase(faultyRepo),
          previewArchive: PreviewBackupArchiveUseCase(faultyRepo),
          restoreArchive: RestoreBackupArchiveUseCase(faultyRepo),
          fileShareService: const MethodChannelBackupFileShareService(),
        );
        addTearDown(bloc.close);

        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          _wrapApp(
            Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: FilledButton(
                    key: const Key('open_partial_sheet'),
                    onPressed: () => showLifeOsBackupRestoreSheet(
                      ctx,
                      userIdOverride: dstUser,
                      backupBlocOverride: bloc,
                    ),
                    child: const Text('Mở'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('open_partial_sheet')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Khôi phục dữ liệu'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('backup_import_payload_field')),
          exportedArchive,
        );
        await tester.tap(find.byKey(const Key('backup_preview_validate_btn')));
        await tester.pumpAndSettle();

        final sheetList = find.byKey(
          const Key('backup_restore_sheet_list_view'),
        );
        await tester.drag(sheetList, const Offset(0, -320));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('backup_apply_restore_btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('backup_apply_restore_btn')));
        await tester.pumpAndSettle();

        expect(find.text('Khôi phục gián đoạn một phần'), findsOneWidget);
        expect(find.text('Khôi phục hoàn tất'), findsNothing);
        expect(find.textContaining('Đã ghi thật: 9'), findsOneWidget);
        expect(find.text('Thử lại khôi phục tiếp'), findsOneWidget);

        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );
  });
}
