import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/error/failure.dart';
import 'package:life_os/core/navigation/feature_registry.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/services/native_home_widget_bridge.dart';
import 'package:life_os/core/services/native_voice_assistant_bridge.dart';
import 'package:life_os/core/utils/csv_sanitizer.dart';
import 'package:life_os/core/utils/omni_action_executor.dart';
import 'package:life_os/core/utils/smart_omni_intent_parser.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:life_os/core/widgets/voice_smart_capture_sheet.dart';
import 'package:life_os/features/authentication/domain/entities/user_entity.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_bloc.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_event.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_state.dart';
import 'package:life_os/features/calendar/data/datasources/google_calendar_api_datasource.dart';
import 'package:life_os/features/calendar/data/repositories/calendar_repository_impl.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/daily_life/data/repositories/daily_life_repository_impl.dart';
import 'package:life_os/features/daily_life/presentation/bloc/daily_life_bloc.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/family/domain/repositories/family_repository.dart';
import 'package:life_os/features/family/domain/usecases/family_usecases.dart';
import 'package:life_os/features/family/presentation/bloc/family_bloc.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:life_os/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_bloc.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_event.dart';
import 'package:mocktail/mocktail.dart';

class _MockTransactionRepository extends Mock
    implements TransactionRepository {}

class _MockFamilyRepository extends Mock implements FamilyRepository {}

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

class _NoOpDeviceCalendarDriver implements DeviceCalendarDriver {
  const _NoOpDeviceCalendarDriver();

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

class _NoOpVoiceDriver implements VoiceAssistantDriver {
  const _NoOpVoiceDriver();

  @override
  bool get isSupportedPlatform => false;

  @override
  Future<String> startListening() async => 'UNSUPPORTED';

  @override
  Future<void> stopListening() async {}

  @override
  Stream<VoiceAssistantSignal> watchSignals() =>
      const Stream<VoiceAssistantSignal>.empty();
}

UserEntity _testUser({String id = 'u_audit_1', String? activeFamilyId}) {
  return UserEntity(
    id: id,
    email: '$id@lifeos.vn',
    fullName: 'Người Dùng Kiểm Toán',
    timezone: 'Asia/Ho_Chi_Minh',
    onboardingCompleted: true,
    availabilityOptIn: true,
    activeFamilyId: activeFamilyId,
    createdAt: DateTime.utc(2026, 11, 24),
  );
}

TransactionEntity _sampleTx({
  required String id,
  required int amountMinor,
  required String merchant,
  TransactionKind kind = TransactionKind.expense,
}) {
  return TransactionEntity(
    id: id,
    ownerId: 'u_audit_1',
    walletId: 'w_cash',
    categoryName: 'Ăn uống',
    kind: kind,
    direction: kind == TransactionKind.income ? 'credit' : 'debit',
    amountMinor: amountMinor,
    merchant: merchant,
    occurredAt: DateTime.utc(2026, 11, 24),
    monthKey: '2026-11',
    sourceKind: TransactionSourceKind.manual,
    verification: TransactionVerification.userConfirmed,
    crossSourceFingerprint: 'fp_$id',
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(WalletType.cash);
    registerFallbackValue(TransactionKind.expense);
    registerFallbackValue(CollaborationSpaceType.family);
  });

  setUp(() async {
    await UserBehaviorPrefs.resetForTest();
    NativeDeviceCalendarBridge.setDriverOverride(
      const _NoOpDeviceCalendarDriver(),
    );
    NativeVoiceAssistantBridge.setDriverOverride(const _NoOpVoiceDriver());
  });

  tearDown(() {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    NativeVoiceAssistantBridge.setDriverOverride(null);
  });

  group('Audit v3.25.0 — P0 & P1 Data Integrity, Privacy & Sync Verification', () {
    testWidgets(
      'P0 (2.1): OmniActionExecutor never shows fake success on write failure and Undo uses real createdTx.id',
      (tester) async {
        final mockTxRepo = _MockTransactionRepository();
        var shouldFail = true;
        String? reversedTxId;

        when(
          () => mockTxRepo.createTransaction(
            operationId: any(named: 'operationId'),
            userId: any(named: 'userId'),
            walletId: any(named: 'walletId'),
            targetWalletId: any(named: 'targetWalletId'),
            categoryId: any(named: 'categoryId'),
            categoryName: any(named: 'categoryName'),
            kind: any(named: 'kind'),
            amountMinor: any(named: 'amountMinor'),
            merchant: any(named: 'merchant'),
            note: any(named: 'note'),
            occurredAt: any(named: 'occurredAt'),
            splitLines: any(named: 'splitLines'),
          ),
        ).thenAnswer((inv) async {
          if (shouldFail) {
            return const Err(
              UnexpectedFailure(message: 'Mất kết nối cơ sở dữ liệu'),
            );
          }
          final amt = inv.namedArguments[#amountMinor] as int;
          final merchant = inv.namedArguments[#merchant] as String;
          return Success(
            _sampleTx(
              id: 'real_firestore_tx_id_888',
              amountMinor: amt,
              merchant: merchant,
            ),
          );
        });

        when(
          () => mockTxRepo.reverseTransaction(
            userId: any(named: 'userId'),
            transactionId: any(named: 'transactionId'),
            reason: any(named: 'reason'),
          ),
        ).thenAnswer((inv) async {
          reversedTxId = inv.namedArguments[#transactionId] as String;
          return Success(
            _sampleTx(
              id: 'rev_888',
              amountMinor: 45000,
              merchant: 'Hoàn tác',
              kind: TransactionKind.reversal,
            ),
          );
        });

        final txActionBloc = TransactionActionBloc(
          createWallet: CreateWalletUseCase(mockTxRepo),
          createTransaction: CreateTransactionUseCase(mockTxRepo),
          reverseTransaction: ReverseTransactionUseCase(mockTxRepo),
          decideProvisional: DecideProvisionalTransactionUseCase(mockTxRepo),
        );

        late BuildContext hostContext;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  hostContext = ctx;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        const draft = OmniActionDraft(
          id: 'draft_coffee_1',
          kind: OmniActionKind.transaction,
          title: 'Cà phê sáng',
          amountMinor: 45000,
          categoryId: 'cat_food',
          categoryName: 'Ăn uống',
        );

        // 1. Repository fails -> must return false & NOT show fake "Đã lưu:" toast!
        bool? failedOk;
        unawaited(
          OmniActionExecutor.executeDraft(
            toastContext: hostContext,
            draft: draft,
            user: _testUser(),
            walletId: 'w_cash',
            txActionBloc: txActionBloc,
          ).then((v) => failedOk = v),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(failedOk, isFalse);
        expect(find.textContaining('Đã lưu: Cà phê sáng'), findsNothing);
        expect(
          find.textContaining('Mất kết nối cơ sở dữ liệu'),
          findsOneWidget,
        );
        expect(UserBehaviorPrefs.topRankedHabits(), isEmpty);

        LifeOsTopToast.dismiss();
        await tester.pump(const Duration(milliseconds: 300));

        // 2. Repository succeeds -> returns true, shows toast, and Undo passes real_firestore_tx_id_888!
        shouldFail = false;
        bool? savedOk;
        unawaited(
          OmniActionExecutor.executeDraft(
            toastContext: hostContext,
            draft: draft,
            user: _testUser(),
            walletId: 'w_cash',
            txActionBloc: txActionBloc,
          ).then((v) => savedOk = v),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(savedOk, isTrue);
        expect(find.textContaining('Đã lưu: Cà phê sáng'), findsOneWidget);
        expect(find.text('Hoàn tác'), findsOneWidget);

        await tester.tap(find.text('Hoàn tác'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(reversedTxId, 'real_firestore_tx_id_888');

        LifeOsTopToast.dismiss();
        await tester.pump(const Duration(seconds: 4));
        unawaited(txActionBloc.close());
      },
    );

    testWidgets(
      'P0/P1 (2.3 & 2.11): VoiceSmartCaptureSheet partial batch failure keeps sheet open and retries ONLY failed item without duplicates',
      (tester) async {
        if (!sl.isRegistered<NativeVoiceAssistantBridge>()) {
          sl.registerLazySingleton<NativeVoiceAssistantBridge>(
            NativeVoiceAssistantBridge.new,
          );
        }

        final mockAuthBloc = _MockAuthBloc();
        final user = _testUser();
        whenListen(
          mockAuthBloc,
          const Stream<AuthState>.empty(),
          initialState: AuthState(status: AuthStatus.authenticated, user: user),
        );

        final mockTxRepo = _MockTransactionRepository();
        final mockFamilyRepo = _MockFamilyRepository();
        final committedMerchants = <String>[];
        final seenOpIdsByMerchant = <String, Set<String>>{};
        var failFuelOnce = true;

        when(() => mockTxRepo.watchWallets(any())).thenAnswer(
          (_) => Stream.value(
            const Success(<WalletEntity>[
              WalletEntity(
                id: 'w_main',
                ownerId: 'u_audit_1',
                name: 'Ví chính',
                type: WalletType.cash,
                balanceMinor: 5000000,
              ),
            ]),
          ),
        );
        when(
          () => mockTxRepo.watchCategories(any()),
        ).thenAnswer((_) => Stream.value(const Success(<CategoryEntity>[])));
        when(
          () => mockTxRepo.watchTransactions(
            userId: any(named: 'userId'),
            monthKey: any(named: 'monthKey'),
          ),
        ).thenAnswer((_) => Stream.value(const Success(<TransactionEntity>[])));
        when(
          () => mockFamilyRepo.watchMyFamilies(any()),
        ).thenAnswer((_) => Stream.value(const Success(<FamilyEntity>[])));

        when(
          () => mockTxRepo.createTransaction(
            operationId: any(named: 'operationId'),
            userId: any(named: 'userId'),
            walletId: any(named: 'walletId'),
            targetWalletId: any(named: 'targetWalletId'),
            categoryId: any(named: 'categoryId'),
            categoryName: any(named: 'categoryName'),
            kind: any(named: 'kind'),
            amountMinor: any(named: 'amountMinor'),
            merchant: any(named: 'merchant'),
            note: any(named: 'note'),
            occurredAt: any(named: 'occurredAt'),
            splitLines: any(named: 'splitLines'),
          ),
        ).thenAnswer((inv) async {
          final opId = inv.namedArguments[#operationId] as String;
          final merchant = inv.namedArguments[#merchant] as String;
          final amt = inv.namedArguments[#amountMinor] as int;
          seenOpIdsByMerchant.putIfAbsent(merchant, () => <String>{}).add(opId);

          if (failFuelOnce && merchant.toLowerCase().contains('xăng')) {
            failFuelOnce = false;
            return const Err(UnexpectedFailure(message: 'Lỗi mạng tạm thời'));
          }
          committedMerchants.add(merchant);
          return Success(
            _sampleTx(id: 'tx_$opId', amountMinor: amt, merchant: merchant),
          );
        });

        final txListBloc = TransactionListBloc(repository: mockTxRepo)
          ..add(
            const TransactionsSubscriptionRequested(
              userId: 'u_audit_1',
              monthKey: '2026-11',
            ),
          );
        final txActionBloc = TransactionActionBloc(
          createWallet: CreateWalletUseCase(mockTxRepo),
          createTransaction: CreateTransactionUseCase(mockTxRepo),
          reverseTransaction: ReverseTransactionUseCase(mockTxRepo),
          decideProvisional: DecideProvisionalTransactionUseCase(mockTxRepo),
        );
        final familyBloc = FamilyBloc(
          repository: mockFamilyRepo,
          createFamily: CreateFamilyUseCase(mockFamilyRepo),
          joinFamily: JoinFamilyByCodeUseCase(mockFamilyRepo),
        );

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: mockAuthBloc),
              BlocProvider<TransactionListBloc>.value(value: txListBloc),
              BlocProvider<TransactionActionBloc>.value(value: txActionBloc),
              BlocProvider<FamilyBloc>.value(value: familyBloc),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => ElevatedButton(
                    key: const Key('open_voice_sheet_btn'),
                    onPressed: () => showVoiceSmartCaptureSheet(
                      ctx,
                      autoStartListening: false,
                      initialTranscript:
                          'Ăn sáng 30 nghìn, đổ xăng 50 nghìn, mua thuốc 100 nghìn',
                    ),
                    child: const Text('Mở Mic'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_voice_sheet_btn')));
        await tester.pumpAndSettle();

        final confirmBtn = find.byKey(
          const Key('confirm_voice_analysis_button'),
        );
        expect(confirmBtn, findsOneWidget);

        // First attempt: item #1 & #3 succeed, item #2 ("đổ xăng") fails -> sheet stays open!
        await tester.ensureVisible(confirmBtn);
        await tester.tap(confirmBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(committedMerchants.length, 2);
        expect(confirmBtn, findsOneWidget); // Sheet stayed open for retry!
        LifeOsTopToast.dismiss();
        await tester.pump(const Duration(milliseconds: 100));

        // Retry: ONLY the failed "đổ xăng" item is submitted, with the SAME deterministic operationId!
        await tester.ensureVisible(confirmBtn);
        await tester.tap(confirmBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));

        expect(committedMerchants.length, 3); // Zero duplicates!
        expect(confirmBtn, findsNothing); // Sheet popped after 3/3 confirmed!
        for (final entry in seenOpIdsByMerchant.entries) {
          expect(
            entry.value.length,
            1,
            reason:
                'Item "${entry.key}" must reuse the same deterministic operationId across retries',
          );
        }

        LifeOsTopToast.dismiss();
        await tester.pump(const Duration(seconds: 4));
        unawaited(txListBloc.close());
        unawaited(txActionBloc.close());
        unawaited(familyBloc.close());
        unawaited(mockAuthBloc.close());
      },
    );

    test(
      'P1 (2.2): FamilyBloc clears stale shoppingItems, sharedBills & settlements immediately when switching groups',
      () async {
        final mockFamilyRepo = _MockFamilyRepository();
        final famBShopCtrl =
            StreamController<Result<List<ShoppingItemEntity>>>();
        final famBBillsCtrl =
            StreamController<Result<List<SharedBillSplitEntity>>>();
        final famBSettleCtrl =
            StreamController<Result<List<DebtSettlementEntity>>>();

        when(() => mockFamilyRepo.watchShoppingItems('fam_a')).thenAnswer(
          (_) => Stream.value(
            const Success(<ShoppingItemEntity>[
              ShoppingItemEntity(
                id: 's_a1',
                familyId: 'fam_a',
                title: 'Gạo ST25 Nhóm A',
                quantityLabel: '1 túi',
                estimatedPriceMinor: 190000,
                isPurchased: false,
                addedByName: 'Lan',
              ),
            ]),
          ),
        );
        when(() => mockFamilyRepo.watchSharedBills('fam_a')).thenAnswer(
          (_) => Stream.value(const Success(<SharedBillSplitEntity>[])),
        );
        when(() => mockFamilyRepo.watchSettlements('fam_a')).thenAnswer(
          (_) => Stream.value(const Success(<DebtSettlementEntity>[])),
        );

        when(
          () => mockFamilyRepo.watchShoppingItems('fam_b'),
        ).thenAnswer((_) => famBShopCtrl.stream);
        when(
          () => mockFamilyRepo.watchSharedBills('fam_b'),
        ).thenAnswer((_) => famBBillsCtrl.stream);
        when(
          () => mockFamilyRepo.watchSettlements('fam_b'),
        ).thenAnswer((_) => famBSettleCtrl.stream);

        final bloc = FamilyBloc(
          repository: mockFamilyRepo,
          createFamily: CreateFamilyUseCase(mockFamilyRepo),
          joinFamily: JoinFamilyByCodeUseCase(mockFamilyRepo),
        );

        bloc.add(const FamilyShoppingWatchRequested('fam_a'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(bloc.state.selectedFamilyId, 'fam_a');
        expect(bloc.state.shoppingItems.single.title, 'Gạo ST25 Nhóm A');

        // Switch to fam_b BEFORE fam_b streams emit anything -> old fam_a items must be wiped immediately!
        bloc.add(const FamilyShoppingWatchRequested('fam_b'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.selectedFamilyId, 'fam_b');
        expect(bloc.state.isLoading, isTrue);
        expect(bloc.state.shoppingItems, isEmpty);
        expect(bloc.state.sharedBills, isEmpty);
        expect(bloc.state.settlements, isEmpty);

        // Once fam_b emits, isLoading becomes false with fam_b's items
        famBShopCtrl.add(
          const Success(<ShoppingItemEntity>[
            ShoppingItemEntity(
              id: 's_b1',
              familyId: 'fam_b',
              title: 'Sữa Tươi Nhóm B',
              quantityLabel: '2 hộp',
              estimatedPriceMinor: 68000,
              isPurchased: false,
              addedByName: 'Minh',
            ),
          ]),
        );
        famBBillsCtrl.add(const Success(<SharedBillSplitEntity>[]));
        famBSettleCtrl.add(const Success(<DebtSettlementEntity>[]));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(bloc.state.isLoading, isFalse);
        expect(bloc.state.shoppingItems.single.title, 'Sữa Tươi Nhóm B');

        await famBShopCtrl.close();
        await famBBillsCtrl.close();
        await famBSettleCtrl.close();
        await bloc.close();
      },
    );

    testWidgets(
      'P1 (2.4): Voice water log executes cleanly into DailyLifeBloc hydration snapshot',
      (tester) async {
        final fakeFs = FakeFirebaseFirestore();
        final repo = DailyLifeRepositoryImpl(fakeFs);
        final dailyBloc = DailyLifeBloc(repo)
          ..add(const DailyLifeWatchStarted('u_water_test'));

        late BuildContext hostCtx;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  hostCtx = ctx;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 30));

        bool? ok;
        unawaited(
          OmniActionExecutor.executeDraft(
            toastContext: hostCtx,
            draft: const OmniActionDraft(
              id: 'water_voice_1',
              kind: OmniActionKind.waterLog,
              title: 'Uống 250ml nước',
              waterMl: 250,
            ),
            user: _testUser(id: 'u_water_test'),
            walletId: 'w_cash',
            dailyBloc: dailyBloc,
            showSuccessToast: false,
          ).then((v) => ok = v),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));

        expect(ok, isTrue);
        expect(dailyBloc.state.snapshot.hydration.waterMl, 250);
        unawaited(dailyBloc.close());
      },
    );

    test(
      'P1 (2.9 & 2.11): UserBehaviorPrefs isolates wallets, PIN, privacy mask & habits per userId and NativeHomeWidgetBridge wipes widgets on sign-out',
      () async {
        UserBehaviorPrefs.bindActiveUser('u_alice');
        await UserBehaviorPrefs.rememberWallet('wallet_alice_private');
        await UserBehaviorPrefs.saveAppPinCode('2468');
        await UserBehaviorPrefs.saveHideBalances(true);
        await UserBehaviorPrefs.recordHabitExecution(
          label: 'Phở Alice 55k',
          commandText: 'Phở Alice 55k',
          categoryName: 'Ăn uống',
          amountMinor: 55000,
        );

        // Switch to User B on the same device -> zero leakage from Alice!
        UserBehaviorPrefs.bindActiveUser('u_bob');
        expect(await UserBehaviorPrefs.loadLastWalletId(), isNull);
        expect(await UserBehaviorPrefs.hasAppPinCode(), isFalse);
        expect(await UserBehaviorPrefs.loadHideBalances(), isFalse);
        expect(await UserBehaviorPrefs.loadHabitShortcuts(), isEmpty);

        await UserBehaviorPrefs.rememberWallet('wallet_bob_salary');

        // Switch back to Alice -> Alice's state is intact and separate from Bob's!
        UserBehaviorPrefs.bindActiveUser('u_alice');
        expect(
          await UserBehaviorPrefs.loadLastWalletId(),
          'wallet_alice_private',
        );
        expect(await UserBehaviorPrefs.verifyAppPinCode('2468'), isTrue);
        expect(await UserBehaviorPrefs.loadHideBalances(), isTrue);
        final aliceHabits = await UserBehaviorPrefs.loadHabitShortcuts();
        expect(aliceHabits.single.label, 'Phở Alice 55k');

        // Sign-out wipes active session & Home Screen Widget sensitive payload + queue!
        UserBehaviorPrefs.clearSessionOnSignOut();
        expect(UserBehaviorPrefs.activeUserId, isNull);
        expect(UserBehaviorPrefs.cachedLastWalletId, isNull);

        final widgetBridge = NativeHomeWidgetBridge()
          ..simulateHomeScreenWidgetCommand(
            const QueuedHomeWidgetCommand(
              id: 'cmd_leak_1',
              kind: 'expense',
              commandText: 'Cà phê 35k',
              amountMinor: 35000,
            ),
            notifyLiveListener: false,
          );
        await widgetBridge.clearWidgetsOnSignOut();
        expect(await widgetBridge.drainQueuedWidgetCommands(), isEmpty);
        expect(widgetBridge.debugLastSyncedPayload?['signedOut'], isTrue);
        expect(widgetBridge.debugLastSyncedPayload?['netWorthMinor'], 0);
        expect(widgetBridge.debugLastSyncedPayload?['hideBalances'], isTrue);
      },
    );

    test(
      'P1 (2.11): CsvSanitizer neutralizes OWASP spreadsheet formula injection while preserving Vietnamese UTF-8',
      () {
        expect(
          CsvSanitizer.escapeQuotedCell('=HYPERLINK("http://evil","Click")'),
          '"\'=HYPERLINK(""http://evil"",""Click"")"',
        );
        expect(
          CsvSanitizer.escapeQuotedCell('+cmd|\' /C calc\'!A0'),
          '"\'+cmd|\' /C calc\'!A0"',
        );
        expect(CsvSanitizer.escapeQuotedCell('-100+200'), '"\'-100+200"');
        expect(CsvSanitizer.escapeQuotedCell('@SUM(A1:A5)'), '"\'@SUM(A1:A5)"');
        expect(
          CsvSanitizer.escapeQuotedCell('  =IMPORTXML("x","y")'),
          '"\'  =IMPORTXML(""x"",""y"")"',
        );
        expect(
          CsvSanitizer.escapeQuotedCell('Phở Thìn "Bờ Hồ"\nHà Nội'),
          '"Phở Thìn ""Bờ Hồ"" Hà Nội"',
        );
      },
    );

    test(
      'P1 (2.8 & 2.7): Google Calendar sync uses composite (googleCalendarId::googleEventId) without collision, cleans family busy-slot on pendingDelete, and FeatureRegistry normalizes ?tab= routes',
      () async {
        expect(
          CalendarRemoteDataSource.googleEventCompositeKey('primary', 'ev_99'),
          isNot(
            CalendarRemoteDataSource.googleEventCompositeKey(
              'team@group.calendar.google.com',
              'ev_99',
            ),
          ),
        );
        expect(
          CalendarRemoteDataSource.googleEventDocId('primary', 'ev_99'),
          'gcal_ev_99',
        );
        expect(
          CalendarRemoteDataSource.googleEventDocId(
            'team@group.calendar.google.com',
            'ev_99',
          ),
          isNot('gcal_ev_99'),
        );

        final fakeFs = FakeFirebaseFirestore();
        await fakeFs.collection('users').doc('u_cal_1').set({
          'activeFamilyId': 'fam_sync_1',
          'availabilityOptIn': true,
        });

        // Seed a local pendingDelete event in private_events + its corresponding family availability busy-slot!
        await fakeFs
            .collection('users')
            .doc('u_cal_1')
            .collection('private_events')
            .doc('ev_to_delete')
            .set({
              'id': 'ev_to_delete',
              'calendarId': 'primary',
              'ownerId': 'u_cal_1',
              'ownerName': 'Minh',
              'familyId': 'fam_sync_1',
              'visibility': CalendarEventVisibility.privateEvent.name,
              'title': 'Họp kín cần xóa',
              'startsAt': Timestamp.fromDate(DateTime.utc(2026, 11, 25, 9)),
              'endsAt': Timestamp.fromDate(DateTime.utc(2026, 11, 25, 10)),
              'googleCalendarId': 'primary',
              'googleEventId': 'g_del_1',
              'syncStatus': CalendarSyncStatus.pendingDelete.name,
            });
        await fakeFs
            .collection('families')
            .doc('fam_sync_1')
            .collection('availability')
            .doc('ev_to_delete')
            .set({
              'id': 'ev_to_delete',
              'userId': 'u_cal_1',
              'label': 'Đang bận',
            });

        var remoteDeleteCalled = false;
        final mockHttp = MockClient((req) async {
          final path = req.url.path;
          if (req.method == 'GET' && path.endsWith('/users/me/calendarList')) {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 'primary',
                    'summary': 'Lịch chính',
                    'primary': true,
                    'selected': true,
                    'accessRole': 'owner',
                  },
                  {
                    'id': 'team@group.calendar.google.com',
                    'summary': 'Lịch Nhóm Dự Án',
                    'primary': false,
                    'selected': true,
                    'accessRole': 'reader',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (req.method == 'DELETE' &&
              path.contains('/calendars/primary/events/g_del_1')) {
            remoteDeleteCalled = true;
            return http.Response('', 204);
          }
          if (req.method == 'GET' &&
              path.contains('/calendars/primary/events')) {
            return http.Response(
              jsonEncode({
                'nextSyncToken': 'tok_primary_1',
                'items': [
                  {
                    'id': 'shared_ev_id_777',
                    'status': 'confirmed',
                    'etag': '"etag_p1"',
                    'summary': 'Sự kiện trên Lịch Chính',
                    'start': {'dateTime': '2026-11-26T02:00:00Z'},
                    'end': {'dateTime': '2026-11-26T03:00:00Z'},
                    'updated': '2026-11-25T01:00:00Z',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (req.method == 'GET' &&
              path.contains('team%40group.calendar.google.com/events')) {
            return http.Response(
              jsonEncode({
                'nextSyncToken': 'tok_team_1',
                'items': [
                  {
                    'id': 'shared_ev_id_777',
                    'status': 'confirmed',
                    'etag': '"etag_t1"',
                    'summary': 'Sự kiện trên Lịch Nhóm Phụ',
                    'start': {'dateTime': '2026-11-26T02:00:00Z'},
                    'end': {'dateTime': '2026-11-26T03:00:00Z'},
                    'updated': '2026-11-25T01:00:00Z',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{}', 404);
        });

        final gApi = GoogleCalendarApiDataSource(
          httpClient: mockHttp,
          tokenProviderOverride: ({required interactive}) async => 'tok_test',
        )..cacheManualAccessToken('tok_test');
        final calDs = CalendarRemoteDataSource(fakeFs, googleApi: gApi);

        final report = await calDs.syncWithGoogleCalendar(
          userId: 'u_cal_1',
          userName: 'Minh',
          interactivePromptIfNeeded: false,
          manualAccessTokenOverride: 'tok_test',
        );

        expect(remoteDeleteCalled, isTrue);
        expect(report.pushedDeleted, 1);

        // Busy-slot in family availability MUST be deleted along with pendingDelete!
        final busySnap = await fakeFs
            .collection('families')
            .doc('fam_sync_1')
            .collection('availability')
            .doc('ev_to_delete')
            .get();
        expect(busySnap.exists, isFalse);

        // Both events sharing googleEventId 'shared_ev_id_777' across 2 calendars MUST coexist without overwriting!
        final eventsSnap = await fakeFs
            .collection('users')
            .doc('u_cal_1')
            .collection('private_events')
            .get();
        final titles = eventsSnap.docs
            .map((d) => d.data()['title'] as String)
            .toSet();
        expect(
          titles,
          containsAll(<String>{
            'Sự kiện trên Lịch Chính',
            'Sự kiện trên Lịch Nhóm Phụ',
          }),
        );

        // Deep-link ?tab= normalization contract
        expect(
          FeatureRegistry.normalizeSmartNotesSalaryTab('salary'),
          'salary',
        );
        expect(FeatureRegistry.normalizeSmartNotesSalaryTab('notes'), 'notes');
        expect(FeatureRegistry.normalizeWealthToolTab('loan'), 'loan');
        expect(FeatureRegistry.normalizeWealthToolTab('fire'), 'fire');
        expect(FeatureRegistry.normalizePlanningTabIndex('tasks'), 1);
        expect(FeatureRegistry.normalizePlanningTabIndex('tools'), 2);
      },
    );
  });
}
