import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/calendar/domain/repositories/calendar_repository.dart';
import 'package:life_os/features/calendar/presentation/bloc/calendar_bloc.dart';

void main() {
  group('Google Calendar API v3: Multi-Calendar, RRULE Recurrence, Update, Delete & Two-Way Delta Sync', () {
    test('RFC 5545 CalendarRecurrenceRule encodes, parses & expands weekly BYDAY and COUNT occurrences accurately', () {
      const rule = CalendarRecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 1,
        byWeekDays: <String>['MO', 'WE', 'FR'],
        count: 5,
      );

      final rrule = rule.toRruleString();
      expect(rrule, 'RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=5');
      expect(rule.humanReadableVi, contains('Hằng tuần (T2, T4, T6) · 5 lần'));

      final reparsed = CalendarRecurrenceRule.fromRruleString(rrule);
      expect(reparsed, rule);

      // Monday 2026-11-23 09:00 -> Mon 23, Wed 25, Fri 27, Mon 30, Wed Dec 2 (5 occurrences total)
      final firstStart = DateTime(2026, 11, 23, 9, 0);
      final occurrences = reparsed.expandOccurrences(
        firstStart: firstStart,
        windowStart: DateTime(2026, 11, 20),
        windowEnd: DateTime(2026, 12, 31),
      );
      expect(occurrences.length, 5);
      expect(occurrences[0].day, 23);
      expect(occurrences[1].day, 25);
      expect(occurrences[2].day, 27);
      expect(occurrences[3].day, 30);
      expect(occurrences[4].month, 12);
      expect(occurrences[4].day, 2);
    });

    test('Full CalendarBloc & GoogleCalendarApiDataSource E2E: Create Secondary Calendar, CRUD Recurring Event, Two-Way Sync & 410 Gone Recovery', () async {
      final insertedPayloads = <Map<String, dynamic>>[];
      final patchedPayloads = <Map<String, dynamic>>[];
      final deletedEventIds = <String>[];
      var syncCallCount = 0;

      final mockHttp = MockClient((request) async {
        final path = request.url.path;
        final method = request.method;

        // 1. Secondary calendar creation: POST /calendar/v3/calendars
        if (method == 'POST' && path.endsWith('/calendars')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 'gcal_work_secondary',
              'summary': body['summary'],
              'description': body['description'],
              'timeZone': 'Asia/Ho_Chi_Minh',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        // CalendarList color patch
        if (method == 'PATCH' && path.contains('/users/me/calendarList/')) {
          return http.Response('{}', 200);
        }

        // 2. CalendarList listing: GET /calendar/v3/users/me/calendarList
        if (method == 'GET' && path.endsWith('/users/me/calendarList')) {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'primary',
                  'summary': 'Lịch Google Chính',
                  'primary': true,
                  'selected': true,
                  'backgroundColor': '#0B7A2A',
                  'timeZone': 'Asia/Ho_Chi_Minh',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        // 3. Insert Event: POST /calendar/v3/calendars/{id}/events
        if (method == 'POST' && path.endsWith('/events')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          insertedPayloads.add(body);
          return http.Response(
            jsonEncode({
              'id': 'g_ev_local_1',
              'etag': '"etag_v1"',
              'status': 'confirmed',
              'summary': body['summary'],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        // 4. Patch Event: PATCH /calendar/v3/calendars/{id}/events/{eventId}
        if (method == 'PATCH' && path.contains('/events/')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          patchedPayloads.add(body);
          return http.Response(
            jsonEncode({
              'id': 'g_ev_local_1',
              'etag': '"etag_v2"',
              'status': 'confirmed',
              'summary': body['summary'],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        // 5. Delete Event: DELETE /calendar/v3/calendars/{id}/events/{eventId}
        if (method == 'DELETE' && path.contains('/events/')) {
          deletedEventIds.add(path.split('/').last);
          return http.Response('', 204);
        }

        // 6. List Events Delta (`syncToken` + 410 Gone recovery!)
        if (method == 'GET' && path.endsWith('/events')) {
          syncCallCount++;
          final tokenParam = request.url.queryParameters['syncToken'];

          // Simulate expired syncToken (410 Gone) on second sync -> client must auto-recover!
          if (tokenParam == 'sync_tok_expired_v1') {
            return http.Response('{"error":{"code":410,"message":"Sync token expired"}}', 410);
          }

          if (syncCallCount == 1) {
            return http.Response(
              jsonEncode({
                'nextSyncToken': 'sync_tok_expired_v1',
                'items': [
                  {
                    'id': 'g_remote_rent',
                    'status': 'confirmed',
                    'etag': '"etag_remote_1"',
                    'summary': 'Đóng tiền trọ & Điện nước',
                    'location': 'Quận 7',
                    'start': {
                      'dateTime': '2026-12-05T02:00:00Z',
                      'timeZone': 'Asia/Ho_Chi_Minh',
                    },
                    'end': {
                      'dateTime': '2026-12-05T03:00:00Z',
                      'timeZone': 'Asia/Ho_Chi_Minh',
                    },
                    'recurrence': ['RRULE:FREQ=MONTHLY'],
                    'updated': '2026-11-22T10:00:00Z',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }

          // After 410 recovery resync, remote cancels 'g_remote_rent'!
          return http.Response(
            jsonEncode({
              'nextSyncToken': 'sync_tok_fresh_v2',
              'items': [
                {
                  'id': 'g_remote_rent',
                  'status': 'cancelled',
                  'updated': '2026-11-22T12:00:00Z',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        return http.Response('{}', 404);
      });

      final fakeFirestore = FakeFirebaseFirestore();
      final mockAuth = MockFirebaseAuth(signedIn: true);

      await configureDependencies(
        authOverride: mockAuth,
        firestoreOverride: fakeFirestore,
        httpClientOverride: mockHttp,
        googleCalendarTokenOverride: ({required interactive}) async => 'ya29.mock_calendar_token',
      );

      final repo = sl<CalendarRepository>();
      final bloc = sl<CalendarBloc>()..add(const CalendarWatchStarted(userId: 'u_cal_1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // A. Create Secondary Calendar directly on Google Calendar
      bloc.add(
        const ManagedCalendarCreateSubmitted(
          CreateManagedCalendarParams(
            userId: 'u_cal_1',
            summary: 'Lịch Dự án Công ty',
            colorHex: '#1971C2',
            createOnGoogle: true,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(bloc.state.calendars.any((c) => c.summary == 'Lịch Dự án Công ty'), isTrue);

      // B. Create Recurring Event (Mon/Wed/Fri Gym) & auto-push to Google Calendar
      final start = DateTime.utc(2026, 11, 23, 10, 0);
      bloc.add(
        CalendarEventCreated(
          CreateCalendarEventParams(
            userId: 'u_cal_1',
            userName: 'Danh Hòa',
            visibility: CalendarEventVisibility.privateEvent,
            title: 'Tập Gym Buổi tối',
            location: 'California Fitness',
            startsAt: start,
            endsAt: start.add(const Duration(hours: 1)),
            recurrence: const CalendarRecurrenceRule(
              frequency: RecurrenceFrequency.weekly,
              byWeekDays: ['MO', 'WE', 'FR'],
            ),
            syncToGoogle: true,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(insertedPayloads.length, 1);
      expect(insertedPayloads.single['recurrence'], ['RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR']);
      final createdLocal = bloc.state.events.firstWhere((e) => e.title == 'Tập Gym Buổi tối');
      expect(createdLocal.syncStatus, CalendarSyncStatus.synced);
      expect(createdLocal.googleEventId, 'g_ev_local_1');

      // C. Update Event (`PATCH /events/g_ev_local_1`)
      bloc.add(
        CalendarEventUpdated(
          UpdateCalendarEventParams(
            userId: 'u_cal_1',
            userName: 'Danh Hòa',
            existingEvent: createdLocal,
            title: 'Tập Gym & Bơi lội',
            location: 'Quận 3',
            startsAt: start,
            endsAt: start.add(const Duration(hours: 2)),
            syncToGoogle: true,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(patchedPayloads.length, 1);
      expect(patchedPayloads.single['summary'], 'Tập Gym & Bơi lội');
      expect(bloc.state.events.any((e) => e.title == 'Tập Gym & Bơi lội'), isTrue);

      // D. Two-Way Sync #1: Pulls remote monthly recurring event 'Đóng tiền trọ & Điện nước'
      final sync1 = await repo.syncWithGoogleCalendar(
        userId: 'u_cal_1',
        userName: 'Danh Hòa',
      );
      expect(sync1.isSuccess, isTrue);
      final report1 = (sync1 as Success<GoogleCalendarSyncReport>).value;
      expect(report1.pulledUpserted, 1);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final pulledRent =
          bloc.state.events.firstWhere((e) => e.title == 'Đóng tiền trọ & Điện nước');
      expect(pulledRent.recurrence.frequency, RecurrenceFrequency.monthly);

      // E. Two-Way Sync #2: Encounters 410 Gone on expired syncToken -> auto-recovers & processes remote cancellation!
      final sync2 = await repo.syncWithGoogleCalendar(
        userId: 'u_cal_1',
        userName: 'Danh Hòa',
      );
      expect(sync2.isSuccess, isTrue);
      final report2 = (sync2 as Success<GoogleCalendarSyncReport>).value;
      expect(report2.pulledDeleted, 1);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(bloc.state.events.any((e) => e.title == 'Đóng tiền trọ & Điện nước'), isFalse);

      // F. Delete synced event -> deletes both locally and on Google Calendar (`DELETE /events/g_ev_local_1`)
      final gymUpdated = bloc.state.events.firstWhere((e) => e.title == 'Tập Gym & Bơi lội');
      bloc.add(
        CalendarEventDeleted(
          userId: 'u_cal_1',
          visibility: CalendarEventVisibility.privateEvent,
          eventId: gymUpdated.id,
          googleCalendarId: gymUpdated.googleCalendarId,
          googleEventId: gymUpdated.googleEventId,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(deletedEventIds, contains('g_ev_local_1'));
      expect(bloc.state.events, isEmpty);

      await bloc.close();
    });
  });
}
