import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/drafts/local_draft_store.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/error/failure.dart';
import 'package:life_os/core/search/global_search_and_command_engine.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/utils/vietnamese_search_matcher.dart';
import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:life_os/core/widgets/omni_command_palette_sheet.dart';
import 'package:life_os/core/widgets/quick_create_hub_sheet.dart';
import 'package:life_os/core/widgets/smart_form_inputs.dart';
import 'package:life_os/features/authentication/domain/entities/user_entity.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_bloc.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_event.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_state.dart';
import 'package:life_os/features/daily_life/domain/entities/daily_life_entities.dart';
import 'package:life_os/features/daily_life/presentation/bloc/daily_life_bloc.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:life_os/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_bloc.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_event.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

class _MockTxListBloc
    extends MockBloc<TransactionListEvent, TransactionListState>
    implements TransactionListBloc {}

class _MockDailyLifeBloc extends MockBloc<DailyLifeEvent, DailyLifeState>
    implements DailyLifeBloc {}

class _MockTransactionRepository extends Mock
    implements TransactionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(TransactionKind.expense);
    registerFallbackValue(DateTime(2026, 11, 25));
    registerFallbackValue(const <TransactionSplitLine>[]);
  });

  tearDown(() async {
    LocalDraftStore.vaultOverride = null;
    LocalDraftStore.clearAllInMemoryCaches();
    await NativeSecureVaultBridge.instance.clearAllSecrets();
  });

  group('1. Account-Scoped Form Draft Persistence (LocalDraftStore)', () {
    test(
      'persists per (userId, formId), stamps ownerUserId, isolates accounts & clears safely',
      () async {
        final vault = NativeSecureVaultBridge.testable();
        LocalDraftStore.vaultOverride = vault;

        await LocalDraftStore.saveDraft(
          userId: 'user_a',
          formId: 'quick_tx_form',
          payload: <String, dynamic>{
            'amountText': '35k',
            'noteText': 'Cà phê sáng',
          },
        );

        // Verify exact vault key naming & ownerUserId stamped inside JSON payload
        final rawStored = await vault.readSecret(
          'ux_form_draft_v1__u_user_a__quick_tx_form',
        );
        expect(rawStored, isNotNull);
        final decoded = jsonDecode(rawStored!) as Map<String, dynamic>;
        expect(decoded['ownerUserId'], 'user_a');
        expect(decoded['amountText'], '35k');

        // Account B MUST NOT receive Account A's draft
        final crossLoad = await LocalDraftStore.loadDraft(
          userId: 'user_b',
          formId: 'quick_tx_form',
        );
        expect(crossLoad, isNull);

        // Tamper defense: even if someone writes Account A's payload under Account B's key
        await vault.writeSecret(
          key: 'ux_form_draft_v1__u_user_b__quick_tx_form',
          value: rawStored,
        );
        final tamperedLoad = await LocalDraftStore.loadDraft(
          userId: 'user_b',
          formId: 'quick_tx_form',
        );
        expect(tamperedLoad, isNull);

        // Clearing in-memory caches still restores from encrypted vault
        LocalDraftStore.clearAllInMemoryCaches();
        final restored = await LocalDraftStore.loadDraft(
          userId: 'user_a',
          formId: 'quick_tx_form',
        );
        expect(restored, isNotNull);
        expect(restored!['noteText'], 'Cà phê sáng');

        // Save another draft for user_a and one for user_b
        await LocalDraftStore.saveDraft(
          userId: 'user_a',
          formId: 'quick_task_form',
          payload: <String, dynamic>{'title': 'Đóng tiền điện'},
        );
        await LocalDraftStore.saveDraft(
          userId: 'user_b',
          formId: 'quick_task_form',
          payload: <String, dynamic>{'title': 'Mua sữa'},
        );

        // Clear all drafts for user_a even after memory cache clear
        LocalDraftStore.clearAllInMemoryCaches();
        await LocalDraftStore.clearAllDraftsForUser('user_a');
        expect(
          await LocalDraftStore.loadDraft(
            userId: 'user_a',
            formId: 'quick_tx_form',
          ),
          isNull,
        );
        expect(
          await LocalDraftStore.loadDraft(
            userId: 'user_a',
            formId: 'quick_task_form',
          ),
          isNull,
        );
        // User B remains completely untouched!
        final userBTask = await LocalDraftStore.loadDraft(
          userId: 'user_b',
          formId: 'quick_task_form',
        );
        expect(userBTask?['title'], 'Mua sữa');
      },
    );
  });

  group('2. SmartVndAmountParser & LifeOsVndSmartAmountField', () {
    test('parses all Vietnamese currency shorthand & compound formats', () {
      expect(SmartVndAmountParser.tryParse('35000'), 35000);
      expect(SmartVndAmountParser.tryParse('35.000'), 35000);
      expect(SmartVndAmountParser.tryParse('35,000 ₫'), 35000);
      expect(SmartVndAmountParser.tryParse('35k'), 35000);
      expect(SmartVndAmountParser.tryParse('35.5k'), 35500);
      expect(SmartVndAmountParser.tryParse('35k5'), 35500);
      expect(SmartVndAmountParser.tryParse('500 nghìn'), 500000);
      expect(SmartVndAmountParser.tryParse('500 ngàn đồng'), 500000);
      expect(SmartVndAmountParser.tryParse('1tr2'), 1200000);
      expect(SmartVndAmountParser.tryParse('1.5tr'), 1500000);
      expect(SmartVndAmountParser.tryParse('1 triệu 200 nghìn'), 1200000);
      expect(SmartVndAmountParser.tryParse('1 triệu rưỡi'), 1500000);
      expect(SmartVndAmountParser.tryParse('năm trăm nghìn'), 500000);
      expect(
        SmartVndAmountParser.tryParse('một triệu hai trăm nghìn'),
        1200000,
      );

      // Invalid / negative / mixed non-amount strings return null
      expect(SmartVndAmountParser.tryParse(''), isNull);
      expect(SmartVndAmountParser.tryParse('0'), isNull);
      expect(SmartVndAmountParser.tryParse('-35000'), isNull);
      expect(SmartVndAmountParser.tryParse('-35k'), isNull);
      expect(SmartVndAmountParser.tryParse('abc'), isNull);
      expect(SmartVndAmountParser.tryParse('phở 35k'), isNull);
      expect(SmartVndAmountParser.tryParse('35k abc'), isNull);
    });

    testWidgets(
      'uses TextInputType.text, shows non-destructive chips for short digits, live tabular readout & 48dp targets',
      (tester) async {
        final ctrl = TextEditingController();
        int? latestAmount;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: LifeOsVndSmartAmountField(
                  fieldKey: const Key('smart_amt_field'),
                  controller: ctrl,
                  onAmountChanged: (v) => latestAmount = v,
                ),
              ),
            ),
          ),
        );

        final tf = tester.widget<TextField>(
          find.byKey(const Key('smart_amt_field')),
        );
        expect(tf.keyboardType, TextInputType.text);

        // Entering '35' shows suggestion chips WITHOUT silently replacing '35'
        await tester.enterText(find.byKey(const Key('smart_amt_field')), '35');
        await tester.pumpAndSettle();
        expect(ctrl.text, '35');
        expect(latestAmount, 35);
        expect(find.byKey(const Key('vnd_zero_pad_35000')), findsOneWidget);
        expect(find.byKey(const Key('vnd_zero_pad_350000')), findsOneWidget);
        expect(find.byKey(const Key('vnd_zero_pad_3500000')), findsOneWidget);

        // Verify >= 48dp touch target on chip
        final chipSize = tester.getSize(
          find.byKey(const Key('vnd_zero_pad_35000')),
        );
        expect(chipSize.height, greaterThanOrEqualTo(48.0));

        // Tap chip -> populates 35000 and updates live readout with tabular figures
        await tester.tap(find.byKey(const Key('vnd_zero_pad_35000')));
        await tester.pumpAndSettle();
        expect(ctrl.text, '35000');
        expect(latestAmount, 35000);
        expect(find.text('Số tiền sẽ lưu: 35.000 ₫'), findsOneWidget);
        final readoutWidget = tester.widget<Text>(
          find.text('Số tiền sẽ lưu: 35.000 ₫'),
        );
        expect(
          readoutWidget.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );

        // Compound format
        await tester.enterText(
          find.byKey(const Key('smart_amt_field')),
          '1 triệu 200 nghìn',
        );
        await tester.pumpAndSettle();
        expect(latestAmount, 1200000);
        expect(find.text('Số tiền sẽ lưu: 1.200.000 ₫'), findsOneWidget);

        // Invalid input shows inline error
        await tester.enterText(find.byKey(const Key('smart_amt_field')), 'abc');
        await tester.pumpAndSettle();
        expect(latestAmount, isNull);
        expect(find.textContaining('Số tiền chưa hợp lệ'), findsOneWidget);

        ctrl.dispose();
      },
    );
  });

  group('3. VietnameseRelativeTimeResolver & LifeOsRelativeDateTimePicker', () {
    test('resolves presets accurately with explicit disambiguation string', () {
      // Wednesday, Nov 25, 2026 at 10:00
      final refNow = DateTime(2026, 11, 25, 10, 0);

      final (in15, exp15, amb15) = VietnameseRelativeTimeResolver.resolve(
        VietnameseRelativeTimePreset.in15Minutes,
        refNow,
      );
      expect(in15, DateTime(2026, 11, 25, 10, 15));
      expect(amb15, isFalse);
      expect(exp15, 'Hiểu là: Thứ Tư, 25/11 lúc 10:15');

      final (today, _, ambToday) = VietnameseRelativeTimeResolver.resolve(
        VietnameseRelativeTimePreset.today,
        refNow,
      );
      expect(today, DateTime(2026, 11, 25, 20, 0));
      expect(ambToday, isFalse);

      final (tomorrow, _, ambTomorrow) = VietnameseRelativeTimeResolver.resolve(
        VietnameseRelativeTimePreset.tomorrow,
        refNow,
      );
      expect(tomorrow, DateTime(2026, 11, 26, 9, 0));
      expect(ambTomorrow, isFalse);

      final (weekend, _, ambWeekend) = VietnameseRelativeTimeResolver.resolve(
        VietnameseRelativeTimePreset.weekend,
        refNow,
      );
      expect(weekend, DateTime(2026, 11, 28, 9, 0));
      expect(ambWeekend, isTrue);

      final (nextMon, expMon, ambMon) = VietnameseRelativeTimeResolver.resolve(
        VietnameseRelativeTimePreset.nextMonday,
        refNow,
      );
      expect(nextMon, DateTime(2026, 11, 30, 9, 0));
      expect(expMon, 'Hiểu là: Thứ Hai, 30/11 lúc 09:00');
      expect(ambMon, isTrue);
    });

    testWidgets('updates disambiguation preview banner when tapping chips', (
      tester,
    ) async {
      var selectedDt = DateTime(2026, 11, 25, 20, 0);
      VietnameseRelativeTimePreset? selectedPreset =
          VietnameseRelativeTimePreset.today;
      var ambiguous = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) => Padding(
                padding: const EdgeInsets.all(16),
                child: LifeOsRelativeDateTimePicker(
                  selectedDateTime: selectedDt,
                  selectedPreset: selectedPreset,
                  isAmbiguous: ambiguous,
                  onChanged: (dt, p, amb) {
                    setState(() {
                      selectedDt = dt;
                      selectedPreset = p;
                      ambiguous = amb;
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Hôm nay'), findsOneWidget);
      expect(find.text('Ngày mai'), findsOneWidget);
      expect(find.text('Cuối tuần'), findsOneWidget);
      expect(find.text('15 phút nữa'), findsOneWidget);
      expect(find.text('Thứ Hai tuần sau'), findsOneWidget);
      expect(find.text('Chọn ngày giờ...'), findsOneWidget);

      await tester.tap(find.text('Thứ Hai tuần sau'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hiểu là: Thứ Hai,'), findsOneWidget);
    });
  });

  group('4. Quick Action Hub, Split Bill, Failure Draft Retention & 360x800@112%', () {
    testWidgets(
      '3-Mode Quick Hub renders all tiles without overflow/vertical-stacking at 360x800 @ 112%, handles multi-intent & manual split sheet',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFirestore = FakeFirebaseFirestore();
        const uid = 'uid_quick_hub_v327';
        await fakeFirestore.collection('users').doc(uid).set({
          'id': uid,
          'email': 'an@lifeos.vn',
          'fullName': 'Nguyễn An',
          'onboardingCompleted': true,
          'availabilityOptIn': false,
        });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_cash_default')
            .set({
              'id': 'wallet_cash_default',
              'ownerId': uid,
              'name': 'Tiền mặt',
              'type': 'cash',
              'balanceMinor': 1500000,
              'isEstimatedBalance': true,
            });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'an@lifeos.vn',
            displayName: 'Nguyễn An',
          ),
        );
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
        );

        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.12)),
            child: LifeOsApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Open Quick Create Hub
        await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
        await tester.pumpAndSettle();

        // Verify all required tiles exist
        for (final key in const [
          Key('quick_hub_smart_input'),
          Key('quick_hub_voice_btn'),
          Key('quick_tile_expense'),
          Key('quick_tile_transfer'),
          Key('quick_tile_split'),
          Key('quick_tile_vehicle_expense'),
          Key('quick_tile_event'),
          Key('quick_tile_task'),
          Key('quick_tile_reminder'),
          Key('quick_tile_note_grocery'),
          Key('quick_tile_qr'),
          Key('quick_hub_water_med_btn'),
        ]) {
          expect(find.byKey(key), findsOneWidget);
        }

        // Check zero RenderFlex overflow, zero didExceedMaxLines, zero narrow vertical stacking inside BottomSheet
        expect(tester.takeException(), isNull);
        for (final element
            in find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(RichText),
                )
                .evaluate()) {
          final ro = element.renderObject;
          if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
          final plain = ro.text.toPlainText().trim();
          if (plain.isEmpty) continue;
          expect(
            ro.didExceedMaxLines,
            isFalse,
            reason: 'Truncated text in Quick Hub: "$plain"',
          );
          if (!plain.contains('\n')) {
            final tp = TextPainter(
              text: ro.text,
              textDirection: ro.textDirection,
              textScaler: ro.textScaler,
              textAlign: ro.textAlign,
            )..layout(maxWidth: ro.size.width + 0.5);
            final lines = tp.computeLineMetrics();
            tp.dispose();
            final words = plain
                .split(RegExp(r'\s+'))
                .where((w) => w.isNotEmpty)
                .toList();
            if (words.length == 2 && plain.length <= 9) {
              expect(
                lines.length,
                lessThan(2),
                reason: '2-word label split across lines: "$plain"',
              );
            }
          }
        }

        // Multi-intent preview & per-draft toggle
        await tester.enterText(
          find.byKey(const Key('quick_hub_smart_input')),
          'Ăn sáng 35k, đổ xăng 70k và nhắc tôi họp vào 14h',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('105.000 ₫'), findsOneWidget);

        // Toggle off first draft -> total updates to 70.000 ₫
        await tester.tap(
          find.byKey(const Key('quick_hub_toggle_draft_omni_tx_0')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('70.000 ₫'), findsWidgets);

        // Close sheet & reopen -> draft is restored from LocalDraftStore!
        await tester.tap(find.byTooltip('Đóng'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
        await tester.pumpAndSettle();
        final restoredInput = tester.widget<TextField>(
          find.byKey(const Key('quick_hub_smart_input')),
        );
        expect(
          restoredInput.controller?.text,
          'Ăn sáng 35k, đổ xăng 70k và nhắc tôi họp vào 14h',
        );

        // Clear draft cleanly and tap quick_tile_split -> opens manual Split Bill sheet (NOT Voice)
        await tester.tap(find.byKey(const Key('quick_hub_clear_input_btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quick_tile_split')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('quick_split_title_input')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('quick_split_amount_input')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('quick_split_voice_btn')), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('quick_split_amount_input')),
          '600k',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('300.000 ₫'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'Quick Transaction sheet enforces double-tap lock, preserves draft & stays open on BLoC failure, clears on success',
      (tester) async {
        final mockAuthBloc = _MockAuthBloc();
        final mockTxListBloc = _MockTxListBloc();
        final mockRepo = _MockTransactionRepository();

        final user = UserEntity(
          id: 'user_tx_test',
          email: 'tx@lifeos.vn',
          fullName: 'Trần Bình',
          timezone: 'Asia/Ho_Chi_Minh',
          onboardingCompleted: true,
          availabilityOptIn: false,
          createdAt: DateTime(2026, 1, 1),
        );
        const wallet = WalletEntity(
          id: 'w_cash',
          ownerId: 'user_tx_test',
          name: 'Tiền mặt',
          type: WalletType.cash,
          balanceMinor: 1000000,
        );

        when(
          () => mockAuthBloc.state,
        ).thenReturn(AuthState(status: AuthStatus.authenticated, user: user));
        when(() => mockTxListBloc.state).thenReturn(
          const TransactionListState(
            monthKey: '2026-11',
            wallets: <WalletEntity>[wallet],
          ),
        );

        var repoCalls = 0;
        var shouldFail = true;
        String? firstOpId;
        String? secondOpId;

        when(
          () => mockRepo.createTransaction(
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
          repoCalls++;
          final opId = inv.namedArguments[#operationId] as String;
          await Future<void>.delayed(const Duration(milliseconds: 80));
          if (shouldFail) {
            firstOpId = opId;
            return const Err(UnexpectedFailure(message: 'Mất kết nối máy chủ'));
          }
          secondOpId = opId;
          return Success(
            TransactionEntity(
              id: opId,
              ownerId: user.id,
              walletId: wallet.id,
              categoryName: 'Ăn uống',
              kind: TransactionKind.expense,
              direction: 'debit',
              amountMinor: 45000,
              merchant: 'Bún bò',
              occurredAt: DateTime(2026, 11, 25),
              monthKey: '2026-11',
              sourceKind: TransactionSourceKind.manual,
              verification: TransactionVerification.userConfirmed,
              crossSourceFingerprint: opId,
            ),
          );
        });

        final txActionBloc = TransactionActionBloc(
          createWallet: CreateWalletUseCase(mockRepo),
          createTransaction: CreateTransactionUseCase(mockRepo),
          reverseTransaction: ReverseTransactionUseCase(mockRepo),
          decideProvisional: DecideProvisionalTransactionUseCase(mockRepo),
        );
        addTearDown(txActionBloc.close);

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: mockAuthBloc),
              BlocProvider<TransactionListBloc>.value(value: mockTxListBloc),
              BlocProvider<TransactionActionBloc>.value(value: txActionBloc),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (_, child) => LifeOsTopToastHost(child: child!),
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => Center(
                    child: ElevatedButton(
                      key: const Key('open_hub_test_btn'),
                      onPressed: () => showLifeOsQuickCreateHubSheet(ctx),
                      child: const Text('Mở Hub'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('open_hub_test_btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quick_tile_expense')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('quick_tx_amount_input')),
          '45k',
        );
        await tester.enterText(
          find.byKey(const Key('quick_tx_note_input')),
          'Bún bò',
        );
        await tester.pumpAndSettle();

        // Rapid double-tap while first submit is in-flight -> MUST only call repo once!
        await tester.tap(find.byKey(const Key('quick_tx_submit_btn')));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.tap(
          find.byKey(const Key('quick_tx_submit_btn')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(repoCalls, 1);
        // On BLoC failure: sheet MUST remain open & draft MUST be preserved!
        expect(find.byKey(const Key('quick_tx_amount_input')), findsOneWidget);
        final keptDraft = await LocalDraftStore.loadDraft(
          userId: user.id,
          formId: 'quick_tx_form',
        );
        expect(keptDraft?['amountText'], '45k');
        expect(keptDraft?['noteText'], 'Bún bò');

        // Retry after backend recovers -> reuses same stable operationId, pops sheet & clears draft
        shouldFail = false;
        await tester.tap(find.byKey(const Key('quick_tx_submit_btn')));
        await tester.pumpAndSettle();

        expect(repoCalls, 2);
        expect(secondOpId, isNotNull);
        expect(secondOpId, firstOpId);
        expect(find.byKey(const Key('quick_tx_amount_input')), findsNothing);
        expect(
          await LocalDraftStore.loadDraft(
            userId: user.id,
            formId: 'quick_tx_form',
          ),
          isNull,
        );
      },
    );

    testWidgets(
      'Quick Transfer, Quick Reminder, Quick Task, Quick Grocery & Direct Event Dialog work end-to-end',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFirestore = FakeFirebaseFirestore();
        const uid = 'uid_quick_flows_v327';
        await fakeFirestore.collection('users').doc(uid).set({
          'id': uid,
          'email': 'flow@lifeos.vn',
          'fullName': 'Lê Minh',
          'onboardingCompleted': true,
          'availabilityOptIn': false,
        });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_cash')
            .set({
              'id': 'w_cash',
              'ownerId': uid,
              'name': 'Tiền mặt',
              'type': 'cash',
              'balanceMinor': 2000000,
              'isEstimatedBalance': true,
            });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_vcb')
            .set({
              'id': 'w_vcb',
              'ownerId': uid,
              'name': 'Vietcombank',
              'type': 'bank',
              'balanceMinor': 5000000,
              'isEstimatedBalance': false,
            });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'flow@lifeos.vn',
            displayName: 'Lê Minh',
          ),
        );
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
        );

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        // 1. Quick Transfer between 2 wallets
        await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quick_tile_transfer')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('quick_transfer_amount_input')),
          '250k',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('250.000 ₫'), findsWidgets);
        await tester.tap(find.byKey(const Key('quick_transfer_submit_btn')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('quick_transfer_amount_input')),
          findsNothing,
        );
        expect(
          await LocalDraftStore.loadDraft(
            userId: uid,
            formId: 'quick_transfer_form',
          ),
          isNull,
        );

        // 2. Quick Reminder with LifeOsRelativeDateTimePicker
        await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quick_tile_reminder')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('quick_reminder_title_input')),
          'Gọi đối tác',
        );
        await tester.tap(find.text('Thứ Hai tuần sau'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Hiểu là: Thứ Hai,'), findsOneWidget);
        await tester.tap(find.byKey(const Key('quick_reminder_submit_btn')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('quick_reminder_title_input')),
          findsNothing,
        );

        // 3. Quick Task with LifeOsRelativeDateTimePicker
        await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quick_tile_task')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('quick_task_title_input')),
          'Nộp hồ sơ',
        );
        await tester.tap(find.text('Ngày mai'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quick_task_submit_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('quick_task_title_input')), findsNothing);

        // 4. Quick Grocery with VND suggestion chips
        await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quick_tile_note_grocery')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('quick_life_title_input')),
          'Thịt bò',
        );
        await tester.enterText(
          find.byKey(const Key('quick_life_detail_input')),
          '85',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('vnd_zero_pad_85000')), findsOneWidget);
        await tester.tap(find.byKey(const Key('vnd_zero_pad_85000')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quick_life_submit_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('quick_life_title_input')), findsNothing);

        // 5. Direct Event Dialog (no transparent dialog hack)
        await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quick_tile_event')));
        await tester.pumpAndSettle();
        expect(find.text('Thêm lịch hẹn mới'), findsOneWidget);
        expect(find.byKey(const Key('event_title_field')), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });

  group('5. Global Search 2.0 (Synonyms, Grouping, Recent Searches & RBAC)', () {
    test(
      'GlobalSearchAndCommandEngine supports bidirectional Vietnamese synonyms, groupByDomain & strict RBAC',
      () {
        const corpus = <SearchableEntityRecord>[
          SearchableEntityRecord(
            id: 'scr_veh',
            domain: SearchDomainKind.appFeature,
            title: 'Xe cộ & Bảo dưỡng',
            subtitle: 'Nhật ký đổ xăng, thay nhớt, ODO',
            targetRoute: '/assets',
            ownerUserId: 'user_a',
            keywords: ['xe may', 'sua xe', 'odo'],
          ),
          SearchableEntityRecord(
            id: 'note_oil',
            domain: SearchDomainKind.note,
            title: 'Lịch thay nhớt định kỳ',
            subtitle: 'Thay dầu mỗi 2000 km',
            targetRoute: '/smart-notes-hub',
            ownerUserId: 'user_a',
          ),
          SearchableEntityRecord(
            id: 'note_wifi',
            domain: SearchDomainKind.note,
            title: 'Wifi tầng 2',
            subtitle: 'Ghi chú riêng',
            targetRoute: '/smart-notes-hub',
            ownerUserId: 'user_a',
          ),
          SearchableEntityRecord(
            id: 'scr_evn',
            domain: SearchDomainKind.appFeature,
            title: 'Điện nước EVN & Nhà cửa',
            subtitle: 'Tính điện 5 bậc, nước & tiền thuê nhà',
            targetRoute: '/home-living',
            ownerUserId: 'user_a',
            keywords: ['evn', 'tien dien', 'phong tro'],
          ),
          SearchableEntityRecord(
            id: 'note_secret_b',
            domain: SearchDomainKind.note,
            title: 'Mật khẩu két sắt của B',
            subtitle: 'Wifi & PIN riêng của B',
            targetRoute: '/smart-notes-hub',
            ownerUserId: 'user_b',
            familyId: 'fam_1',
            isPrivateToOwner: true,
          ),
        ];

        // Bidirectional: 'thay nhot' -> finds 'Xe cộ & Bảo dưỡng' + 'Lịch thay nhớt'
        final oilHits = GlobalSearchAndCommandEngine.search(
          rawQuery: 'thay nhot',
          activeUserId: 'user_a',
          corpus: corpus,
          allowedFamilyIds: const {'fam_1'},
        );
        expect(oilHits.map((h) => h.record.id), contains('scr_veh'));
        expect(oilHits.map((h) => h.record.id), contains('note_oil'));

        // Reverse direction: 'bao duong' -> finds 'Lịch thay nhớt định kỳ'
        final maintHits = GlobalSearchAndCommandEngine.search(
          rawQuery: 'bao duong',
          activeUserId: 'user_a',
          corpus: corpus,
        );
        expect(maintHits.map((h) => h.record.id), contains('note_oil'));

        // 'tien nha' -> 'Điện nước EVN & Nhà cửa'
        final rentHits = GlobalSearchAndCommandEngine.search(
          rawQuery: 'tien nha',
          activeUserId: 'user_a',
          corpus: corpus,
        );
        expect(rentHits.map((h) => h.record.id), contains('scr_evn'));

        // 'mat khau' -> finds user_a's Wifi note, NEVER user_b's private note
        final pwHits = GlobalSearchAndCommandEngine.search(
          rawQuery: 'mat khau',
          activeUserId: 'user_a',
          corpus: corpus,
          allowedFamilyIds: const {'fam_1'},
        );
        expect(pwHits.map((h) => h.record.id), contains('note_wifi'));
        expect(
          pwHits.map((h) => h.record.id),
          isNot(contains('note_secret_b')),
        );

        // 'chia bill' -> finds Chia tiền command
        final splitHits = GlobalSearchAndCommandEngine.search(
          rawQuery: 'chia bill',
          activeUserId: 'user_a',
          corpus: corpus,
        );
        expect(splitHits.map((h) => h.record.id), contains('cmd_split_bill'));

        // 'tien dien' -> finds EVN
        final evnHits = GlobalSearchAndCommandEngine.search(
          rawQuery: 'tien dien',
          activeUserId: 'user_a',
          corpus: corpus,
        );
        expect(evnHits.map((h) => h.record.id), contains('scr_evn'));

        // groupByDomain preserves highest-scoring domain order
        final grouped = GlobalSearchAndCommandEngine.groupByDomain(oilHits);
        expect(grouped.keys, isNotEmpty);
        final firstDomainMax = grouped.values.first.first.score;
        for (final list in grouped.values) {
          expect(firstDomainMax, greaterThanOrEqualTo(list.first.score));
        }

        // VietnameseSearchMatcher numeric shorthand matching
        expect(
          VietnameseSearchMatcher.matchesAny('35k', ['Cà phê', '35.000 ₫']),
          isTrue,
        );
        expect(
          VietnameseSearchMatcher.matchesAny('1tr2', [
            'Tiền nhà',
            '1.200.000 ₫',
          ]),
          isTrue,
        );
      },
    );

    testWidgets(
      'OmniCommandPaletteSheet persists account-scoped recent searches, groups results by domain & enforces dailySnap RBAC',
      (tester) async {
        final mockAuthBloc = _MockAuthBloc();
        final mockDailyBloc = _MockDailyLifeBloc();

        final userA = UserEntity(
          id: 'user_search_a',
          email: 'a@lifeos.vn',
          fullName: 'User A',
          timezone: 'Asia/Ho_Chi_Minh',
          onboardingCompleted: true,
          availabilityOptIn: false,
          createdAt: DateTime(2026, 1, 1),
        );

        when(
          () => mockAuthBloc.state,
        ).thenReturn(AuthState(status: AuthStatus.authenticated, user: userA));

        // Inject a snapshot containing both User A's note AND User B's private note
        when(() => mockDailyBloc.state).thenReturn(
          DailyLifeState(
            snapshot: DailyLifeSnapshot(
              notes: <SmartLifeNoteEntity>[
                SmartLifeNoteEntity(
                  id: 'n_a',
                  ownerId: 'user_search_a',
                  title: 'Mật khẩu Wifi nhà A',
                  content: '12345678',
                  updatedAt: DateTime(2026, 11, 25),
                ),
                SmartLifeNoteEntity(
                  id: 'n_b',
                  ownerId: 'user_search_b',
                  title: 'Mật khẩu bí mật nhà B',
                  content: '99999999',
                  updatedAt: DateTime(2026, 11, 25),
                ),
              ],
            ),
          ),
        );

        // Pre-seed recent searches for user A and user B separately
        await NativeSecureVaultBridge.instance.writeSecret(
          key: 'ux_recent_searches_v1__u_user_search_a',
          value: jsonEncode(['thay nhớt', 'tiền điện']),
        );
        await NativeSecureVaultBridge.instance.writeSecret(
          key: 'ux_recent_searches_v1__u_user_search_b',
          value: jsonEncode(['bí mật B']),
        );

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: mockAuthBloc),
              BlocProvider<DailyLifeBloc>.value(value: mockDailyBloc),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => Center(
                    child: ElevatedButton(
                      key: const Key('open_omni_test_btn'),
                      onPressed: () => showLifeOsOmniCommandPaletteSheet(ctx),
                      child: const Text('Mở Tìm kiếm'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('open_omni_test_btn')));
        await tester.pumpAndSettle();

        // Recent searches for User A shown; User B's NEVER leaks!
        expect(find.text('Tìm kiếm gần đây'), findsOneWidget);
        expect(find.text('thay nhớt'), findsOneWidget);
        expect(find.text('tiền điện'), findsOneWidget);
        expect(find.text('bí mật B'), findsNothing);

        // Clear recent searches via 1-tap button
        await tester.tap(
          find.byKey(const Key('omni_clear_recent_searches_btn')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Tìm kiếm gần đây'), findsNothing);
        expect(
          await NativeSecureVaultBridge.instance.readSecret(
            'ux_recent_searches_v1__u_user_search_a',
          ),
          isNull,
        );
        expect(
          await NativeSecureVaultBridge.instance.readSecret(
            'ux_recent_searches_v1__u_user_search_b',
          ),
          isNotNull,
        );

        // Search 'mật khẩu' -> finds grouped results + User A's note, NEVER User B's note!
        await tester.enterText(
          find.byKey(const Key('omni_search_text_field')),
          'mật khẩu',
        );
        await tester.pump(const Duration(milliseconds: 160));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('omni_group_header_appFeature')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('omni_group_header_note')), findsOneWidget);
        expect(find.text('Bảo mật & Mã PIN'), findsOneWidget);
        expect(find.text('Mật khẩu Wifi nhà A'), findsOneWidget);
        expect(find.text('Mật khẩu bí mật nhà B'), findsNothing);

        // Submit search -> recorded into recent searches for user A
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        final savedRecent = await NativeSecureVaultBridge.instance.readSecret(
          'ux_recent_searches_v1__u_user_search_a',
        );
        expect(savedRecent, contains('mật khẩu'));
      },
    );
  });
}
