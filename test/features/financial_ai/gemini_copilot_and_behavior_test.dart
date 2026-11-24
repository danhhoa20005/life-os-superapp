import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/utils/smart_omni_intent_parser.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/features/financial_ai/data/datasources/gemini_remote_datasource.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/financial_ai/data/repositories/gemini_copilot_repository_impl.dart';
import 'package:life_os/features/financial_ai/presentation/bloc/gemini_copilot_bloc.dart';
import 'package:life_os/features/tasks/domain/entities/task_entities.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';

class _NoOpCalendarDriver implements DeviceCalendarDriver {
  const _NoOpCalendarDriver();

  @override
  bool get isSupportedPlatform => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<List<DeviceCalendarInfo>> listCalendars() async =>
      const <DeviceCalendarInfo>[];

  @override
  Future<List<DeviceCalendarEventItem>> listEvents({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async => const <DeviceCalendarEventItem>[];

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

void main() {
  setUp(() async {
    await NativeSecureVaultBridge.instance.clearAllSecrets();
    await UserBehaviorPrefs.resetForTest();
    NativeDeviceCalendarBridge.setDriverOverride(const _NoOpCalendarDriver());
  });

  tearDown(() async {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    await sl.reset();
  });

  group('1. GeminiPrivacySanitizer & UserBehaviorPrefs RFM Synthesis', () {
    test('Masks phone numbers, emails, and raw bank accounts while preserving VND amounts', () {
      const raw =
          'Chuyển 1.500.000đ cho 0912345678 STK 19036888999012 email hoa@example.com và ăn phở 55k';
      final sanitized = GeminiPrivacySanitizer.sanitize(raw);

      expect(sanitized, contains('[ẨN_SĐT]'));
      expect(sanitized, contains('[ẨN_SỐ_TK]'));
      expect(sanitized, contains('[ẨN_EMAIL]'));
      expect(sanitized, isNot(contains('0912345678')));
      expect(sanitized, isNot(contains('19036888999012')));
      expect(sanitized, isNot(contains('hoa@example.com')));
      expect(sanitized, contains('1.500.000đ'));
      expect(sanitized, contains('55k'));
    });

    test('RFM + Circadian time-of-day ranking prioritizes matching hour habits', () async {
      final morning8am = DateTime(2026, 11, 24, 8, 15);
      final evening8pm = DateTime(2026, 11, 24, 20, 15);

      await UserBehaviorPrefs.recordHabitExecution(
        label: 'Highlands 45k',
        commandText: 'Highlands 45k',
        categoryName: 'Ăn uống',
        amountMinor: 45000,
        now: morning8am,
      );
      await UserBehaviorPrefs.recordHabitExecution(
        label: 'Highlands 45k',
        commandText: 'Highlands 45k',
        categoryName: 'Ăn uống',
        amountMinor: 45000,
        now: morning8am,
      );
      await UserBehaviorPrefs.recordHabitExecution(
        label: 'Siêu thị 180k',
        commandText: 'Đi siêu thị 180k',
        categoryName: 'Chợ & Mua sắm',
        amountMinor: 180000,
        now: evening8pm,
      );

      final morningTop = UserBehaviorPrefs.topRankedHabits(now: morning8am);
      expect(morningTop.first.label, 'Highlands 45k');

      final morningChips = UserBehaviorPrefs.contextualSmartChips(morning8am);
      expect(morningChips.first.isPersonalHabit, isTrue);
      expect(morningChips.first.label, 'Highlands 45k');
      expect(morningChips.length, lessThanOrEqualTo(4));
    });
  });

  group('2. SmartOmniIntentParser (< 2ms Multi-Domain Vietnamese NLP)', () {
    final fixedNow = DateTime(2026, 11, 24, 10, 0); // Tuesday

    test('Parses multi-clause sentence into Expense + Calendar Event + Task', () {
      final drafts = SmartOmniIntentParser.parseMulti(
        'Sáng ăn phở 55k, chiều mai 15h họp dự án và nhắc đóng tiền điện tối nay !gấp',
        now: fixedNow,
      );

      expect(drafts.length, 3);

      expect(drafts[0].kind, OmniActionKind.transaction);
      expect(drafts[0].amountMinor, 55000);
      expect(drafts[0].transactionKind, TransactionKind.expense);
      expect(drafts[0].categoryName, 'Ăn uống');

      expect(drafts[1].kind, OmniActionKind.calendarEvent);
      expect(drafts[1].scheduledAt, DateTime(2026, 11, 25, 15, 0));
      expect(drafts[1].title.toLowerCase(), contains('họp dự án'));

      expect(drafts[2].kind, OmniActionKind.task);
      expect(drafts[2].taskPriority, TaskPriorityLevel.high);
      expect(drafts[2].title.toLowerCase(), contains('đóng tiền điện'));
    });

    test('Parses Splitwise-style group bill split and multi-item grocery command', () {
      final splitDraft = SmartOmniIntentParser.tryParsePrimary(
        'Ăn lẩu bò 600k chia 4 người',
        now: fixedNow,
      );
      expect(splitDraft, isNotNull);
      expect(splitDraft!.kind, OmniActionKind.groupSplit);
      expect(splitDraft.amountMinor, 600000);
      expect(splitDraft.participantCount, 4);
      expect(splitDraft.perPersonShareMinor, 150000);

      final groceries = SmartOmniIntentParser.parseMulti(
        'Đi chợ mua sữa tươi, trứng gà, rau cải',
        now: fixedNow,
      );
      expect(groceries.length, 3);
      expect(
        groceries.every((g) => g.kind == OmniActionKind.grocery),
        isTrue,
      );
    });
  });

  group('3. GeminiCopilotBloc & Hybrid Offline-Fallback Verification', () {
    test('Sends x-goog-api-key header (never in URL), scrubs PII, and parses structured JSON', () async {
      Uri? capturedUri;
      Map<String, String>? capturedHeaders;
      String? capturedBody;

      final mockHttp = MockClient((req) async {
        capturedUri = req.url;
        capturedHeaders = req.headers;
        capturedBody = req.body;

        final geminiPayload = <String, dynamic>{
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode({
                      'assistantInsightVi':
                          'Bạn vẫn nằm trong nhịp chi tiêu an toàn hôm nay.',
                      'transactions': [
                        {
                          'type': 'expense',
                          'amountMinor': 65000,
                          'categoryName': 'Ăn uống',
                          'merchant': 'Bún bò Huế',
                        },
                      ],
                      'calendarEvents': [
                        {
                          'title': 'Họp thiết kế sản phẩm',
                          'startsAtIso': '2026-11-25T09:00:00',
                          'durationMinutes': 45,
                        },
                      ],
                      'tasks': [
                        {
                          'title': 'Gửi biên bản họp',
                          'dueAtIso': '2026-11-25T17:00:00',
                          'priority': 'high',
                        },
                      ],
                    }),
                  },
                ],
              },
            },
          ],
        };
        return http.Response.bytes(
          utf8.encode(jsonEncode(geminiPayload)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final repo = GeminiCopilotRepositoryImpl(
        GeminiRemoteDataSource(httpClient: mockHttp),
      );
      final bloc = GeminiCopilotBloc(repository: repo);

      bloc.add(const GeminiCopilotInitialized());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      bloc.add(
        const GeminiConnectionTestRequested(
          candidateApiKey: 'AIzaSyTestSecretKey9876',
          modelId: 'gemini-2.5-flash',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(bloc.state.config.isReadyForCloud, isTrue);
      expect(bloc.state.config.maskedApiKey, 'AIza••••9876');
      expect(capturedUri.toString(), isNot(contains('AIzaSyTestSecretKey9876')));
      expect(capturedHeaders?['x-goog-api-key'], 'AIzaSyTestSecretKey9876');

      bloc.add(
        GeminiOmniAnalyzeRequested(
          rawInput: 'Ăn bún bò 65k gọi số 0909123456, 9h sáng mai họp thiết kế',
          referenceTime: DateTime(2026, 11, 24, 12, 0),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(capturedBody, contains('[ẨN_SĐT]'));
      expect(capturedBody, isNot(contains('0909123456')));

      final res = bloc.state.lastResult;
      expect(res, isNotNull);
      expect(res!.usedGeminiCloud, isTrue);
      expect(res.usedOfflineFallback, isFalse);
      expect(res.actionDrafts.length, 3);
      expect(res.assistantInsightVi, contains('nhịp chi tiêu an toàn'));

      await bloc.close();
    });

    test('Gracefully falls back to Offline Engine when Gemini returns 429 or is offline', () async {
      final rateLimitedHttp = MockClient((_) async {
        return http.Response('{"error":{"code":429}}', 429);
      });

      final ds = GeminiRemoteDataSource(httpClient: rateLimitedHttp);
      await ds.writeConfig(
        newApiKey: 'AIzaSyQuotaTestKey1234',
        enabled: true,
      );
      final repo = GeminiCopilotRepositoryImpl(ds);

      final result = await repo.analyzeHybridOmniCommand(
        rawInput: 'Đổ xăng 70k và nhắc đóng tiền nước tối nay',
        referenceTime: DateTime(2026, 11, 24, 18, 0),
      );

      expect(result.isSuccess, isTrue);
      result.fold(
        (_) => fail('Expected graceful offline fallback, not failure'),
        (hybrid) {
          expect(hybrid.usedGeminiCloud, isFalse);
          expect(hybrid.usedOfflineFallback, isTrue);
          expect(hybrid.actionDrafts.length, 2);
          expect(hybrid.actionDrafts.first.amountMinor, 70000);
          expect(hybrid.actionDrafts.last.kind, OmniActionKind.task);
        },
      );
    });
  });

  group('4. Full App UI Integration: Gemini Settings & Today Circadian Strip', () {
    testWidgets('Navigates to Gemini AI Settings and Quick Create Omni Bar cleanly at 360x800', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final firestore = FakeFirebaseFirestore();
      final mockUser = MockUser(
        isAnonymous: false,
        uid: 'u_gemini_test',
        email: 'gemini@lifeos.vn',
        displayName: 'Minh Hòa',
      );
      await firestore.collection('users').doc('u_gemini_test').set({
        'email': 'gemini@lifeos.vn',
        'fullName': 'Minh Hòa',
        'onboardingCompleted': true,
        'privacy': {'shareSalaryWithFamily': false},
      });
      final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

      final mockHttp = MockClient((_) async {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text': '{"status":"ok","assistantInsightVi":"Sẵn sàng","transactions":[]}',
                      },
                    ],
                  },
                },
              ],
            }),
          ),
          200,
        );
      });

      await configureDependencies(
        authOverride: auth,
        firestoreOverride: firestore,
        httpClientOverride: mockHttp,
        googleCalendarTokenOverride: ({required interactive}) async => null,
        financialClassifierOverride: FastTextClassifier(useWorkerIsolate: false),
      );

      await tester.pumpWidget(const LifeOsApp());
      await tester.pumpAndSettle();

      // Verify Gemini AI header action on TodayPage & absence of removed Circadian Strip
      expect(find.byKey(const Key('today_open_gemini_ai_pill')), findsOneWidget);
      expect(find.byKey(const Key('today_circadian_smart_strip')), findsNothing);

      // Tap Gemini AI button in Top Header -> opens FinancialAiAssistantPage
      await tester.tap(find.byKey(const Key('today_open_gemini_ai_pill')));
      await tester.pumpAndSettle();
      expect(find.text('Trợ lý AI & Liên kết Gemini'), findsOneWidget);

      // Open Gemini & AI Settings page
      await tester.tap(find.byTooltip('Cài đặt AI & Liên kết Gemini'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gemini_connection_studio_card')), findsOneWidget);

      // Enter API key and verify connection (card is right at the top above the fold)
      await tester.enterText(
        find.byKey(const Key('gemini_api_key_input')),
        'AIzaSyLiveWidgetKey5566',
      );
      await tester.tap(find.byKey(const Key('btn_verify_gemini_connection')));
      await tester.pumpAndSettle();

      expect(find.text('Đã nối Gemini'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
