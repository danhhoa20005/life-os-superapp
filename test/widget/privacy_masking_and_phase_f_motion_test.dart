import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/motion/lifeos_motion.dart';
import 'package:life_os/core/services/native_alarm_scheduler_bridge.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_bloc.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_event.dart';
import 'package:life_os/features/budgets/presentation/bloc/budget_bloc.dart';
import 'package:life_os/features/calendar/presentation/bloc/calendar_bloc.dart';
import 'package:life_os/features/daily_life/presentation/bloc/daily_life_bloc.dart';
import 'package:life_os/features/daily_life/presentation/pages/health_medical_hub_page.dart';
import 'package:life_os/features/documents/presentation/bloc/document_vault_bloc.dart';
import 'package:life_os/features/documents/presentation/pages/family_documents_page.dart';
import 'package:life_os/features/family/presentation/bloc/family_bloc.dart';
import 'package:life_os/features/family/presentation/pages/family_page.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/tasks/presentation/bloc/task_bloc.dart';

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

Widget _buildTestApp({required Widget home}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('vi', 'VN'), Locale('en', 'US')],
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(
          size: const Size(360, 800),
          textScaler: const TextScaler.linear(1.12),
        ),
        child: LifeOsMotionHost(
          child: LifeOsTopToastHost(child: child ?? const SizedBox.shrink()),
        ),
      );
    },
    home: home,
  );
}

Future<void> _configureMockSession({
  required String uid,
  required String email,
  required String fullName,
  String? activeFamilyId,
  Future<void> Function(FakeFirebaseFirestore firestore)? seedFirestore,
}) async {
  final firestore = FakeFirebaseFirestore();
  final nowIso = DateTime(2026, 11, 20).toIso8601String();
  await firestore.collection('users').doc(uid).set(<String, dynamic>{
    'id': uid,
    'email': email,
    'fullName': fullName,
    'phoneNumber': '0912345678',
    'timezone': 'Asia/Ho_Chi_Minh',
    'onboardingCompleted': true,
    'availabilityOptIn': false,
    if (activeFamilyId != null) 'activeFamilyId': activeFamilyId,
    'createdAt': nowIso,
  });

  if (seedFirestore != null) {
    await seedFirestore(firestore);
  }

  final mockUser = MockUser(
    isAnonymous: false,
    uid: uid,
    email: email,
    displayName: fullName,
    isEmailVerified: true,
  );
  final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

  await configureDependencies(
    authOverride: auth,
    firestoreOverride: firestore,
    httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
    googleCalendarTokenOverride: ({required interactive}) async => null,
    financialClassifierOverride: FastTextClassifier(useWorkerIsolate: false),
  );
}

Future<void> _ensureVisibleInViewport(
  WidgetTester tester,
  Finder target, {
  Finder? listViewFinder,
}) async {
  var attempts = 0;
  while (target.evaluate().isEmpty && attempts < 5) {
    final lv = listViewFinder ?? find.byType(ListView).first;
    await tester.drag(lv, const Offset(0, -220));
    await tester.pumpAndSettle();
    attempts++;
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await UserBehaviorPrefs.resetForTest();
    NativeAlarmSchedulerBridge.instance.resetDebugCounters();
    NativeDeviceCalendarBridge.setDriverOverride(
      const _NoOpDeviceCalendarDriver(),
    );
  });

  tearDown(() async {
    await UserBehaviorPrefs.resetForTest();
    NativeAlarmSchedulerBridge.instance.resetDebugCounters();
    NativeDeviceCalendarBridge.setDriverOverride(null);
    await sl.reset();
  });

  group('Privacy Masking & Phase F Motion Widget Suite (360x800 @ 112%)', () {
    testWidgets(
      '1. FamilyDocumentsPage masks referenceCode & note by default and toggles reveal/hide cleanly',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const userId = 'u_doc_privacy_01';
        const docId = 'doc_vault_secret_01';

        await _configureMockSession(
          uid: userId,
          email: 'hosogiayto@lifeos.vn',
          fullName: 'Nguyễn Văn An',
          seedFirestore: (firestore) async {
            await firestore
                .collection('users')
                .doc(userId)
                .collection('documents')
                .doc(docId)
                .set(<String, dynamic>{
                  'id': docId,
                  'ownerId': userId,
                  'uploadedBy': userId,
                  'uploadedByName': 'Nguyễn Văn An',
                  'isFamilyShared': false,
                  'folder': 'important_docs',
                  'title': 'Căn cước công dân gắn chip',
                  'referenceCode': '079200012345',
                  'note': 'Cất ngăn kéo tủ khóa số 2',
                  'storageLifecycle': 'metadataCloudSynced',
                  'createdAt': DateTime(2026, 11, 20).toIso8601String(),
                });
          },
        );

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<ThemeBloc>(create: (_) => sl<ThemeBloc>()),
              BlocProvider<AuthBloc>(
                create: (_) =>
                    sl<AuthBloc>()..add(const AuthSubscriptionRequested()),
              ),
              BlocProvider<DocumentVaultBloc>(
                create: (_) =>
                    sl<DocumentVaultBloc>()
                      ..add(const DocumentVaultWatchStarted(userId: userId)),
              ),
            ],
            child: _buildTestApp(home: const FamilyDocumentsPage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final toggleBtn = find.byKey(
          const Key('toggle_doc_sensitive_doc_vault_secret_01'),
        );
        await _ensureVisibleInViewport(tester, toggleBtn);
        expect(tester.takeException(), isNull);

        // Masked by default
        expect(find.text('Căn cước công dân gắn chip'), findsOneWidget);
        expect(find.text('Mã tham chiếu: •••• 2345'), findsOneWidget);
        expect(
          find.text('•••••••• (Nhấn biểu tượng mắt để xem)'),
          findsOneWidget,
        );
        expect(find.textContaining('079200012345'), findsNothing);
        expect(find.textContaining('Cất ngăn kéo tủ khóa số 2'), findsNothing);

        // Reveal on tap
        await tester.tap(toggleBtn);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('Mã tham chiếu: 079200012345'), findsOneWidget);
        expect(find.text('Cất ngăn kéo tủ khóa số 2'), findsOneWidget);
        expect(find.text('Mã tham chiếu: •••• 2345'), findsNothing);
        expect(
          find.text('•••••••• (Nhấn biểu tượng mắt để xem)'),
          findsNothing,
        );

        // Hide again on second tap
        await _ensureVisibleInViewport(tester, toggleBtn);
        await tester.tap(toggleBtn);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('Mã tham chiếu: •••• 2345'), findsOneWidget);
        expect(
          find.text('•••••••• (Nhấn biểu tượng mắt để xem)'),
          findsOneWidget,
        );
        expect(find.textContaining('079200012345'), findsNothing);
        expect(find.textContaining('Cất ngăn kéo tủ khóa số 2'), findsNothing);
      },
    );

    testWidgets(
      '2. HealthMedicalHubPage(initialTab: sos) masks insuranceCode & emergencyContactPhone by default and reveals on toggle',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const userId = 'u_health_sos_01';

        await _configureMockSession(
          uid: userId,
          email: 'yte.sos@lifeos.vn',
          fullName: 'Lê Hoàng Nam',
          seedFirestore: (firestore) async {
            await firestore
                .collection('users')
                .doc(userId)
                .collection('medical_profiles')
                .doc('emergency_card')
                .set(<String, dynamic>{
                  'bloodType': 'O+',
                  'allergies': 'Penicillin',
                  'chronicConditions': 'Không có',
                  'insuranceCode': 'DN4790012345678',
                  'emergencyContactName': 'Nguyễn Thị Mai',
                  'emergencyContactPhone': '0909112233',
                  'preferredHospital': 'Bệnh viện Chợ Rẫy',
                });
          },
        );

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<ThemeBloc>(create: (_) => sl<ThemeBloc>()),
              BlocProvider<AuthBloc>(
                create: (_) =>
                    sl<AuthBloc>()..add(const AuthSubscriptionRequested()),
              ),
              BlocProvider<DailyLifeBloc>(
                create: (_) =>
                    sl<DailyLifeBloc>()
                      ..add(const DailyLifeWatchStarted(userId)),
              ),
            ],
            child: _buildTestApp(
              home: const HealthMedicalHubPage(initialTab: 'sos'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final toggleMedicalBtn = find.byKey(
          const Key('toggle_medical_sensitive_btn'),
        );
        await _ensureVisibleInViewport(tester, toggleMedicalBtn);
        expect(tester.takeException(), isNull);

        // Masked by default
        expect(find.text('•••• 5678'), findsOneWidget);
        expect(find.textContaining('090•••••33'), findsOneWidget);
        expect(find.textContaining('DN4790012345678'), findsNothing);
        expect(find.textContaining('0909112233'), findsNothing);

        // Reveal on tap
        await tester.tap(toggleMedicalBtn);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('DN4790012345678'), findsOneWidget);
        expect(find.textContaining('0909112233'), findsOneWidget);
        expect(find.text('•••• 5678'), findsNothing);
        expect(find.textContaining('090•••••33'), findsNothing);

        // Re-mask on second tap
        await _ensureVisibleInViewport(tester, toggleMedicalBtn);
        await tester.tap(toggleMedicalBtn);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('•••• 5678'), findsOneWidget);
        expect(find.textContaining('090•••••33'), findsOneWidget);
        expect(find.textContaining('DN4790012345678'), findsNothing);
        expect(find.textContaining('0909112233'), findsNothing);
      },
    );

    testWidgets(
      '3. FamilyPage (Members tab) masks pending inviteCode & inviteeContact by default and reveals on toggle',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const userId = 'u_family_owner_01';
        const familyId = 'fam_privacy_space_01';
        final now = DateTime.now();

        await _configureMockSession(
          uid: userId,
          email: 'chunha@lifeos.vn',
          fullName: 'Trần Minh Quân',
          activeFamilyId: familyId,
          seedFirestore: (firestore) async {
            await firestore.collection('families').doc(familyId).set(
              <String, dynamic>{
                'id': familyId,
                'name': 'Tổ ấm Minh Quân',
                'spaceType': 'family',
                'createdBy': userId,
                'memberIds': <String>[userId],
                'memberRoles': <String, String>{userId: 'owner'},
                'memberNames': <String, String>{userId: 'Trần Minh Quân'},
                'pendingInvites': <String, dynamic>{
                  'FAM-8K2P9Q': <String, dynamic>{
                    'inviteCode': 'FAM-8K2P9Q',
                    'familyId': familyId,
                    'familyName': 'Tổ ấm Minh Quân',
                    'spaceType': 'family',
                    'createdBy': userId,
                    'invitedByName': 'Trần Minh Quân',
                    'inviteeName': 'Trần Lan',
                    'inviteeContact': '0988776655',
                    'revoked': false,
                    'createdAt': Timestamp.fromDate(now),
                    'expiresAt': Timestamp.fromDate(
                      now.add(const Duration(days: 6)),
                    ),
                  },
                },
                'createdAt': Timestamp.fromDate(now),
                'updatedAt': Timestamp.fromDate(now),
              },
            );
          },
        );

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<ThemeBloc>(create: (_) => sl<ThemeBloc>()),
              BlocProvider<AuthBloc>(
                create: (_) =>
                    sl<AuthBloc>()..add(const AuthSubscriptionRequested()),
              ),
              BlocProvider<FamilyBloc>(
                create: (_) => sl<FamilyBloc>()
                  ..add(
                    const FamilySubscriptionRequested(
                      userId: userId,
                      preferredFamilyId: familyId,
                    ),
                  ),
              ),
              BlocProvider<TaskBloc>(create: (_) => sl<TaskBloc>()),
              BlocProvider<CalendarBloc>(create: (_) => sl<CalendarBloc>()),
              BlocProvider<BudgetBloc>(create: (_) => sl<BudgetBloc>()),
            ],
            child: _buildTestApp(home: const FamilyPage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Open "Thành viên" tab
        final membersTab = find.byKey(const Key('family_members_tab'));
        await tester.tap(membersTab);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final toggleInviteChip = find.byKey(
          const Key('toggle_invite_code_FAM-8K2P9Q'),
        );
        await _ensureVisibleInViewport(
          tester,
          toggleInviteChip,
          listViewFinder: find.byKey(const Key('members_list_view')),
        );
        expect(tester.takeException(), isNull);

        // Masked by default
        expect(find.text('FAM-••••9Q'), findsOneWidget);
        expect(find.text('098•••••55'), findsOneWidget);
        expect(find.textContaining('FAM-8K2P9Q'), findsNothing);
        expect(find.textContaining('0988776655'), findsNothing);

        // Reveal on tap
        await tester.tap(toggleInviteChip);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('FAM-8K2P9Q'), findsOneWidget);
        expect(find.text('0988776655'), findsOneWidget);
        expect(find.text('FAM-••••9Q'), findsNothing);
        expect(find.text('098•••••55'), findsNothing);

        // Re-mask on second tap
        await _ensureVisibleInViewport(
          tester,
          toggleInviteChip,
          listViewFinder: find.byKey(const Key('members_list_view')),
        );
        await tester.tap(toggleInviteChip);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('FAM-••••9Q'), findsOneWidget);
        expect(find.text('098•••••55'), findsOneWidget);
        expect(find.textContaining('FAM-8K2P9Q'), findsNothing);
        expect(find.textContaining('0988776655'), findsNothing);
      },
    );

    testWidgets(
      '4. Phase F Motion & Accessibility: OS Reduce Motion precedence, truthful tabular readout & one-shot tracker',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const reducedPrefs = LifeOsMotionPreferences(
          userMode: LifeOsMotionMode.standard,
          platformDisableAnimations: true,
          platformReduceMotion: true,
        );
        expect(reducedPrefs.isReducedMotion, isTrue);
        expect(reducedPrefs.isMotionOff, isTrue);
        expect(
          reducedPrefs.resolveDuration(const Duration(milliseconds: 240)),
          Duration.zero,
        );

        final tracker = LifeOsOneShotEffectTracker();
        expect(tracker.consumeOnce('tx_confirmed_2026_01'), isTrue);
        expect(tracker.consumeOnce('tx_confirmed_2026_01'), isFalse);
        expect(tracker.hasConsumed('tx_confirmed_2026_01'), isTrue);

        var detailsVisible = false;

        await tester.pumpWidget(
          _buildTestApp(
            home: LifeOsMotionScope.overrideForTest(
              preferences: reducedPrefs,
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setModalState) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LifeOsTruthfulNumericText(
                          formattedValue: '15.250.000 ₫',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextButton(
                          key: const Key('toggle_motion_panel_btn'),
                          onPressed: () => setModalState(
                            () => detailsVisible = !detailsVisible,
                          ),
                          child: const Text('Đổi trạng thái hiển thị'),
                        ),
                        LifeOsAnimatedVisibility(
                          visible: detailsVisible,
                          child: const Text('Chi tiết bảo mật mở rộng'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('15.250.000 ₫'), findsOneWidget);
        expect(find.text('Chi tiết bảo mật mở rộng'), findsNothing);

        await tester.tap(find.byKey(const Key('toggle_motion_panel_btn')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Chi tiết bảo mật mở rộng'), findsOneWidget);
      },
    );
  });
}
