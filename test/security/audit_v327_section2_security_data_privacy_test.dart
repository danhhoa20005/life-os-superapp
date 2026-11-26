import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/error/failure.dart';
import 'package:life_os/core/services/native_home_widget_bridge.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/utils/qr_matrix_encoder.dart';
import 'package:life_os/core/utils/vietqr_emv_builder.dart';
import 'package:life_os/core/widgets/offline_qr_code_view.dart';
import 'package:life_os/features/authentication/domain/entities/user_entity.dart';
import 'package:life_os/features/authentication/domain/repositories/auth_repository.dart';
import 'package:life_os/features/authentication/domain/usecases/auth_usecases.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_bloc.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_event.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_state.dart';
import 'package:life_os/features/daily_life/data/repositories/daily_life_repository_impl.dart';
import 'package:life_os/features/daily_life/domain/entities/daily_life_entities.dart';
import 'package:life_os/features/daily_life/presentation/bloc/daily_life_bloc.dart';
import 'package:life_os/features/financial_ai/data/datasources/gemini_remote_datasource.dart';
import 'package:life_os/features/financial_ai/data/repositories/gemini_copilot_repository_impl.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  group('Audit v3.27.0+45 Section 2 — Security, Data Integrity & Privacy Suite', () {
    test(
      '2.1 Widget queued commands are retained across unacknowledged reads and removed only on explicit ledger ACK',
      () async {
        final bridge = NativeHomeWidgetBridge();
        const cmd = QueuedHomeWidgetCommand(
          id: 'w_cmd_35k_1',
          kind: 'expense',
          commandText: 'Cà phê 35000đ',
          label: 'Cà phê',
          amountMinor: 35000,
          createdAtEpochMs: 1732500000000,
        );

        bridge.simulateHomeScreenWidgetCommand(cmd, notifyLiveListener: false);

        // First read (e.g. before user auth or before ledger write finishes) MUST NOT lose the command
        final firstRead = await bridge.drainQueuedWidgetCommands();
        expect(firstRead.length, 1);
        expect(firstRead.single.id, 'w_cmd_35k_1');

        // Second read (e.g. app restart / retry after transient failure) still sees the unacknowledged command
        final secondRead = await bridge.drainQueuedWidgetCommands();
        expect(secondRead.length, 1);
        expect(secondRead.single.id, 'w_cmd_35k_1');

        // Explicit ACK after ledger commit removes the command so it is never duplicated
        final ackCount = await bridge.acknowledgeWidgetCommands(const <String>[
          'w_cmd_35k_1',
        ], feedback: 'Đã ghi: Cà phê (35.000 ₫)');
        expect(ackCount, 1);

        final thirdRead = await bridge.drainQueuedWidgetCommands();
        expect(thirdRead, isEmpty);
      },
    );

    test(
      '2.2 Quick-create medication reminder does not fabricate 30 pills or +270d expiry, and legacy unconfirmed records require confirmation',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = DailyLifeRepositoryImpl(firestore);
        final bloc = DailyLifeBloc(repo);
        addTearDown(bloc.close);
        const uid = 'u_med_quick_audit';

        // Seed a legacy quick-create medication document (30 pills, no inventoryConfirmedAt)
        await firestore
            .collection('users')
            .doc(uid)
            .collection('medications')
            .doc('med_legacy_quick')
            .set(<String, dynamic>{
              'id': 'med_legacy_quick',
              'ownerId': uid,
              'name': 'Vitamin D3 cũ',
              'dosage': '1 viên',
              'slot': MedicationScheduleSlot.morning.name,
              'remainingPills': 30,
              'expiryDate': DateTime.now()
                  .add(const Duration(days: 270))
                  .toIso8601String(),
              'inventoryConfirmed': true,
              'reminderEnabled': true,
              'reminderHour': 7,
              'reminderMinute': 30,
            });

        bloc.add(const DailyLifeWatchStarted(uid));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Legacy 30-pill record without inventoryConfirmedAt must be treated as unconfirmed
        final legacyMed = bloc.state.snapshot.medications.single;
        expect(legacyMed.inventoryConfirmed, isFalse);
        expect(legacyMed.remainingPills, 0);
        expect(legacyMed.isExpiringSoon(DateTime.now()), isFalse);

        // Quick-create a new reminder without stock/expiry
        bloc.add(
          MedicationCabinetAdded(
            userId: uid,
            name: 'Panadol Extra',
            dosage: '1 viên sau ăn',
            slot: MedicationScheduleSlot.evening,
            reminderEnabled: true,
            reminderHour: 20,
            reminderMinute: 0,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));

        final panadol = bloc.state.snapshot.medications.firstWhere(
          (m) => m.name == 'Panadol Extra',
        );
        expect(panadol.inventoryConfirmed, isFalse);
        expect(panadol.remainingPills, 0);
        expect(panadol.isExpiringSoon(DateTime.now()), isFalse);

        // Once the user explicitly updates inventory, inventoryConfirmed becomes true
        final confirmedExpiry = DateTime(2027, 12, 31);
        bloc.add(
          MedicationInventoryUpdated(
            userId: uid,
            item: panadol,
            remainingPills: 16,
            expiryDate: confirmedExpiry,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));

        final updatedPanadol = bloc.state.snapshot.medications.firstWhere(
          (m) => m.name == 'Panadol Extra',
        );
        expect(updatedPanadol.inventoryConfirmed, isTrue);
        expect(updatedPanadol.remainingPills, 16);
      },
    );

    test(
      '2.3 Gemini API key & opt-in are strictly isolated per account and legacy unscoped keys are purged',
      () async {
        final vault = NativeSecureVaultBridge.testable();
        // Pre-seed a legacy unscoped key from v3.27.0
        await vault.writeSecret(
          key: 'gemini_ai_api_key_v1',
          value: 'AIzaSyLEGACY_GLOBAL_KEY_12345',
        );
        await vault.writeSecret(
          key: 'gemini_ai_config_v1',
          value: '{"enabled":true}',
        );

        var geminiHttpCalls = 0;
        final mockHttp = MockClient((req) async {
          geminiHttpCalls += 1;
          return http.Response(
            '{"candidates":[{"content":{"parts":[{"text":"{\\"assistantInsightVi\\":\\"OK\\",\\"drafts\\":[]}"}]}}]}',
            200,
          );
        });

        String? activeUid = 'uid_account_a';
        final remote = GeminiRemoteDataSource(
          httpClient: mockHttp,
          vault: vault,
        );
        final repo = GeminiCopilotRepositoryImpl(
          remote,
          userIdProvider: () => activeUid,
        );

        // 1. First read purges legacy unscoped key and starts unconfigured
        final initialCfg = (await repo.loadConfig()).fold(
          (_) => null,
          (c) => c,
        )!;
        expect(initialCfg.hasApiKey, isFalse);
        expect(initialCfg.enabled, isFalse);
        expect(await vault.readSecret('gemini_ai_api_key_v1'), isNull);

        // 2. Account A saves its own Gemini API key and enables cloud assistant
        final savedA = (await repo.saveConnectionSettings(
          newApiKey: 'AIzaSyAccountA_SecretKey_99999',
          enabled: true,
        )).fold((_) => null, (c) => c)!;
        expect(savedA.hasApiKey, isTrue);
        expect(savedA.enabled, isTrue);

        // 3. Switch to Account B on the same device -> must see "Chưa kết nối" (disabled, no key)
        activeUid = 'uid_account_b';
        final cfgB = (await repo.loadConfig()).fold((_) => null, (c) => c)!;
        expect(cfgB.hasApiKey, isFalse);
        expect(cfgB.enabled, isFalse);
        expect(cfgB.maskedApiKey, isEmpty);

        // 4. Running hybrid analysis under Account B makes ZERO network requests to Google
        final analysisB = await repo.analyzeHybridOmniCommand(
          rawInput: 'Ăn trưa 45k và tư vấn chi tiêu tuần này giúp tôi',
        );
        expect(analysisB.isSuccess, isTrue);
        expect(geminiHttpCalls, 0);
      },
    );

    test(
      '2.4 AuthBloc keeps authenticated state and surfaces SIGN_OUT_FAILED when Firebase signOut fails',
      () async {
        final mockRepo = _MockAuthRepository();
        final userA = UserEntity(
          id: 'u_signout_1',
          email: 'user@lifeos.vn',
          fullName: 'Trần Minh',
          emailVerified: true,
          timezone: 'Asia/Ho_Chi_Minh',
          onboardingCompleted: true,
          availabilityOptIn: false,
          createdAt: DateTime(2026, 11, 25),
        );

        when(
          () => mockRepo.watchCurrentUser(),
        ).thenAnswer((_) => Stream<UserEntity?>.value(userA));

        final bloc = AuthBloc(
          watchCurrentUser: WatchCurrentUserUseCase(mockRepo),
          signIn: SignInUseCase(mockRepo),
          signUp: SignUpUseCase(mockRepo),
          signInWithGoogle: SignInWithGoogleUseCase(mockRepo),
          linkGoogleAccount: LinkGoogleAccountUseCase(mockRepo),
          sendPasswordReset: SendPasswordResetUseCase(mockRepo),
          sendEmailVerification: SendEmailVerificationUseCase(mockRepo),
          reloadCurrentUser: ReloadCurrentUserUseCase(mockRepo),
          updateUserProfile: UpdateUserProfileUseCase(mockRepo),
          changePassword: ChangePasswordUseCase(mockRepo),
          completeOnboarding: CompleteOnboardingUseCase(mockRepo),
          updatePrivacySettings: UpdatePrivacySettingsUseCase(mockRepo),
          signOut: SignOutUseCase(mockRepo),
        );
        addTearDown(bloc.close);

        bloc.add(const AuthSubscriptionRequested());
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(bloc.state.status, AuthStatus.authenticated);
        expect(bloc.state.user?.id, 'u_signout_1');

        // 1. Simulate signOut failure -> state MUST stay authenticated with SIGN_OUT_FAILED
        when(() => mockRepo.signOut()).thenAnswer(
          (_) async => const Err(
            NetworkFailure(message: 'Mất kết nối máy chủ xác thực'),
          ),
        );
        bloc.add(const AuthSignOutRequested());
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(bloc.state.status, AuthStatus.authenticated);
        expect(bloc.state.user?.id, 'u_signout_1');
        expect(bloc.state.failure?.code, 'SIGN_OUT_FAILED');

        // 2. Retry signOut when network recovers -> transitions to unauthenticated
        when(
          () => mockRepo.signOut(),
        ).thenAnswer((_) async => const Success(null));
        bloc.add(const AuthSignOutRequested());
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(bloc.state.status, AuthStatus.unauthenticated);
        expect(bloc.state.user, isNull);
        expect(bloc.state.failure, isNull);
      },
    );

    testWidgets(
      '2.5 VietQR renders 100% offline on-device from emvQrPayload with zero requests to img.vietqr.io',
      (tester) async {
        final emvPayload = VietQrEmvBuilder.buildNapas247Payload(
          bankBin: '970436',
          accountNumber: '0123456789',
          amountVnd: 250000,
          memo: 'LO123456 Tien an trua',
        );
        final visualUri = VietQrEmvBuilder.buildVisualQrUrl(
          bankBin: '970436',
          accountNumber: '0123456789',
          accountHolderName: 'NGUYEN VAN A',
          amountVnd: 250000,
          memo: 'LO123456 Tien an trua',
        );
        expect(visualUri.contains('img.vietqr.io'), isFalse);
        expect(visualUri.startsWith('http'), isFalse);

        final matrix = QrMatrixEncoder.encode(emvPayload);
        expect(matrix.size, greaterThanOrEqualTo(29));
        // Top-left, top-right, bottom-left finder patterns have dark outer corner (0,0)
        expect(matrix.isDark(0, 0), isTrue);
        expect(matrix.isDark(0, matrix.size - 1), isTrue);
        expect(matrix.isDark(matrix.size - 1, 0), isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: OfflineVietQrView(
                  payload: emvPayload,
                  paymentCode: 'LO123456',
                  size: 196,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('offline_vietqr_canvas')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
