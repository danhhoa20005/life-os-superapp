import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../../../app/config/firebase_config.dart';
import '../../../../core/error/app_exception.dart';
import '../../domain/entities/calendar_entities.dart';

class GoogleCalendarRemoteItem {
  final String googleEventId;
  final String status; // 'confirmed', 'tentative', 'cancelled'
  final String? etag;
  final String summary;
  final String? description;
  final String? location;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isAllDay;
  final String timeZone;
  final CalendarRecurrenceRule recurrence;
  final int reminderMinutesBefore;
  final DateTime updatedAt;

  const GoogleCalendarRemoteItem({
    required this.googleEventId,
    required this.status,
    this.etag,
    required this.summary,
    this.description,
    this.location,
    required this.startsAt,
    required this.endsAt,
    required this.isAllDay,
    required this.timeZone,
    required this.recurrence,
    required this.reminderMinutesBefore,
    required this.updatedAt,
  });

  bool get isCancelled => status == 'cancelled';
}

class GoogleCalendarEventsDeltaPage {
  final List<GoogleCalendarRemoteItem> items;
  final String? nextSyncToken;
  final bool usedIncrementalSyncToken;

  const GoogleCalendarEventsDeltaPage({
    required this.items,
    required this.nextSyncToken,
    required this.usedIncrementalSyncToken,
  });
}

typedef GoogleCalendarTokenProvider = Future<String?> Function({required bool interactive});

/// Official Google Calendar REST API v3 client (`https://www.googleapis.com/calendar/v3`).
class GoogleCalendarApiDataSource {
  static const String baseUrl = 'https://www.googleapis.com/calendar/v3';
  static const List<String> calendarScopes = <String>[
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/calendar.events',
  ];

  final FirebaseAuth _firebaseAuth;
  final http.Client _httpClient;
  final GoogleCalendarTokenProvider? _tokenProviderOverride;

  String? _cachedAccessToken;
  DateTime? _cachedTokenExpiresAt;

  GoogleCalendarApiDataSource({
    required FirebaseAuth firebaseAuth,
    http.Client? httpClient,
    GoogleCalendarTokenProvider? tokenProviderOverride,
  })  : _firebaseAuth = firebaseAuth,
        _httpClient = httpClient ?? http.Client(),
        _tokenProviderOverride = tokenProviderOverride;

  bool get hasAuthorizedToken =>
      _cachedAccessToken != null &&
      _cachedAccessToken!.isNotEmpty &&
      (_cachedTokenExpiresAt == null || DateTime.now().isBefore(_cachedTokenExpiresAt!));

  void cacheManualAccessToken(String token) {
    _cachedAccessToken = token.trim();
    _cachedTokenExpiresAt = DateTime.now().add(const Duration(minutes: 50));
  }

  Future<String> acquireAccessToken({
    bool interactive = true,
    String? manualTokenOverride,
  }) async {
    if (manualTokenOverride != null && manualTokenOverride.trim().isNotEmpty) {
      cacheManualAccessToken(manualTokenOverride);
      return _cachedAccessToken!;
    }

    if (hasAuthorizedToken) {
      return _cachedAccessToken!;
    }

    final overrideProvider = _tokenProviderOverride;
    if (overrideProvider != null) {
      final provided = await overrideProvider(interactive: interactive);
      if (provided != null && provided.isNotEmpty) {
        cacheManualAccessToken(provided);
        return provided;
      }
    }

    if (kIsWeb) {
      if (!interactive) {
        throw const AppException(
          code: 'AUTH_REQUIRED',
          message: 'Cần xác thực quyền truy cập Google Calendar.',
        );
      }
      final provider = GoogleAuthProvider()
        ..addScope(calendarScopes.first)
        ..addScope(calendarScopes.last)
        ..setCustomParameters(const {'prompt': 'consent'});
      final cred = await _firebaseAuth.signInWithPopup(provider);
      final oauthCred = cred.credential;
      final token = oauthCred is OAuthCredential ? oauthCred.accessToken : null;
      if (token == null || token.isEmpty) {
        throw const AppException(
          code: 'AUTH_FAILURE',
          message: 'Không nhận được OAuth Access Token cho Google Calendar.',
        );
      }
      cacheManualAccessToken(token);
      return token;
    }

    try {
      await FirebaseConfig.ensureGoogleSignInInitialized();
      final headers = await GoogleSignIn.instance.authorizationClient.authorizationHeaders(
        calendarScopes,
        promptIfNecessary: interactive,
      );
      final authHeader = headers?['Authorization'] ?? '';
      if (authHeader.startsWith('Bearer ')) {
        final token = authHeader.substring(7).trim();
        if (token.isNotEmpty) {
          cacheManualAccessToken(token);
          return token;
        }
      }
      if (interactive) {
        final account = await GoogleSignIn.instance.authenticate(scopeHint: calendarScopes);
        final authz = await account.authorizationClient.authorizeScopes(calendarScopes);
        if (authz.accessToken.isNotEmpty) {
          cacheManualAccessToken(authz.accessToken);
          return authz.accessToken;
        }
      }
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AppException(
          code: 'AUTH_CANCELED',
          message: 'Bạn đã hủy cấp quyền kết nối Google Calendar.',
        );
      }
      throw AppException(
        code: 'GCAL_OAUTH_CONFIG',
        message:
            'Cần hoàn tất OAuth SHA-1 trên Firebase Cloud hoặc nhập OAuth Access Token để đồng bộ Google Calendar (${e.code.name}).',
      );
    }

    throw const AppException(
      code: 'AUTH_REQUIRED',
      message: 'Chưa cấp quyền OAuth cho Google Calendar API.',
    );
  }

  Map<String, String> _headers(String accessToken) => <String, String>{
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      };

  Future<void> _invalidateIfUnauthorized(int statusCode, String accessToken) async {
    if (statusCode == 401) {
      _cachedAccessToken = null;
      _cachedTokenExpiresAt = null;
      if (!kIsWeb && FirebaseConfig.isGoogleSignInInitialized) {
        try {
          await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(
            accessToken: accessToken,
          );
        } catch (_) {}
      }
    }
  }

  /// `GET /users/me/calendarList`
  Future<List<ManagedCalendarEntity>> listCalendars({
    required String accessToken,
    required String ownerId,
  }) async {
    final uri = Uri.parse('$baseUrl/users/me/calendarList?minAccessRole=writer');
    final resp = await _httpClient.get(uri, headers: _headers(accessToken));
    await _invalidateIfUnauthorized(resp.statusCode, accessToken);
    if (resp.statusCode != 200) {
      throw AppException(
        code: 'GCAL_API_ERROR',
        message: 'Google CalendarList trả mã lỗi HTTP ${resp.statusCode}.',
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final rawItems = (data['items'] as List<dynamic>?) ?? const <dynamic>[];
    final result = <ManagedCalendarEntity>[];

    for (final item in rawItems) {
      if (item is! Map<String, dynamic>) continue;
      final gId = (item['id'] as String?) ?? '';
      if (gId.isEmpty) continue;
      final isPrimary = (item['primary'] as bool?) ?? false;
      result.add(
        ManagedCalendarEntity(
          id: isPrimary ? 'primary' : _sanitizeDocId(gId),
          ownerId: ownerId,
          summary: (item['summary'] as String?) ?? 'Lịch Google',
          description: item['description'] as String?,
          timeZone: (item['timeZone'] as String?) ?? 'Asia/Ho_Chi_Minh',
          colorHex: (item['backgroundColor'] as String?) ?? '#0B7A2A',
          isPrimary: isPrimary,
          isSelected: (item['selected'] as bool?) ?? true,
          source: CalendarProviderSource.googleCalendar,
          googleCalendarId: gId,
        ),
      );
    }
    return result;
  }

  /// `POST /calendars` — creates a new secondary Google Calendar on the user's account.
  Future<ManagedCalendarEntity> createSecondaryCalendar({
    required String accessToken,
    required String ownerId,
    required String summary,
    String? description,
    String timeZone = 'Asia/Ho_Chi_Minh',
    String colorHex = '#0B7A2A',
  }) async {
    final resp = await _httpClient.post(
      Uri.parse('$baseUrl/calendars'),
      headers: _headers(accessToken),
      body: jsonEncode(<String, dynamic>{
        'summary': summary,
        if (description != null && description.isNotEmpty) 'description': description,
        'timeZone': timeZone,
      }),
    );
    await _invalidateIfUnauthorized(resp.statusCode, accessToken);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AppException(
        code: 'GCAL_CREATE_CALENDAR_ERROR',
        message: 'Không thể tạo bộ lịch trên Google Calendar (HTTP ${resp.statusCode}).',
      );
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final gId = (body['id'] as String?) ?? '';

    // Apply custom background color in CalendarList best-effort
    if (gId.isNotEmpty) {
      try {
        await _httpClient.patch(
          Uri.parse(
            '$baseUrl/users/me/calendarList/${Uri.encodeComponent(gId)}?colorRgbFormat=true',
          ),
          headers: _headers(accessToken),
          body: jsonEncode(<String, dynamic>{
            'backgroundColor': colorHex,
            'foregroundColor': '#ffffff',
          }),
        );
      } catch (_) {}
    }

    return ManagedCalendarEntity(
      id: _sanitizeDocId(gId),
      ownerId: ownerId,
      summary: (body['summary'] as String?) ?? summary,
      description: body['description'] as String?,
      timeZone: (body['timeZone'] as String?) ?? timeZone,
      colorHex: colorHex,
      isPrimary: false,
      isSelected: true,
      source: CalendarProviderSource.googleCalendar,
      googleCalendarId: gId,
    );
  }

  /// `DELETE /calendars/{calendarId}`
  Future<void> deleteSecondaryCalendar({
    required String accessToken,
    required String googleCalendarId,
  }) async {
    if (googleCalendarId == 'primary') return;
    final resp = await _httpClient.delete(
      Uri.parse('$baseUrl/calendars/${Uri.encodeComponent(googleCalendarId)}'),
      headers: _headers(accessToken),
    );
    await _invalidateIfUnauthorized(resp.statusCode, accessToken);
    if (resp.statusCode != 204 && resp.statusCode != 200 && resp.statusCode != 404 && resp.statusCode != 410) {
      throw AppException(
        code: 'GCAL_DELETE_CALENDAR_ERROR',
        message: 'Không thể xóa bộ lịch trên Google Calendar (HTTP ${resp.statusCode}).',
      );
    }
  }

  /// `GET /calendars/{calendarId}/events` with incremental `syncToken` and automatic `410 Gone` recovery.
  Future<GoogleCalendarEventsDeltaPage> listEventsDelta({
    required String accessToken,
    required String googleCalendarId,
    String? syncToken,
    DateTime? fullSyncTimeMin,
  }) async {
    final encodedCalId = Uri.encodeComponent(googleCalendarId);
    final collected = <GoogleCalendarRemoteItem>[];
    String? pageToken;
    String? nextSyncToken;
    final usingIncremental = syncToken != null && syncToken.trim().isNotEmpty;

    while (true) {
      final query = <String, String>{
        'singleEvents': 'false',
        'showDeleted': 'true',
        'maxResults': '250',
        if (pageToken != null) 'pageToken': pageToken,
      };
      if (usingIncremental) {
        query['syncToken'] = syncToken.trim();
      } else {
        final minDt =
            (fullSyncTimeMin ?? DateTime.now().subtract(const Duration(days: 90))).toUtc();
        query['timeMin'] = minDt.toIso8601String();
      }

      final uri = Uri.parse('$baseUrl/calendars/$encodedCalId/events')
          .replace(queryParameters: query);
      final resp = await _httpClient.get(uri, headers: _headers(accessToken));
      await _invalidateIfUnauthorized(resp.statusCode, accessToken);

      // Official Google Calendar API spec: HTTP 410 Gone means syncToken expired -> full resync!
      if (resp.statusCode == 410 && usingIncremental) {
        return listEventsDelta(
          accessToken: accessToken,
          googleCalendarId: googleCalendarId,
          syncToken: null,
          fullSyncTimeMin: fullSyncTimeMin,
        );
      }

      if (resp.statusCode != 200) {
        throw AppException(
          code: 'GCAL_LIST_EVENTS_ERROR',
          message: 'Lỗi đồng bộ danh sách sự kiện Google Calendar (HTTP ${resp.statusCode}).',
        );
      }

      final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
      final rawItems = (jsonMap['items'] as List<dynamic>?) ?? const <dynamic>[];
      for (final raw in rawItems) {
        if (raw is Map<String, dynamic>) {
          final parsed = _parseRemoteEvent(raw);
          if (parsed != null) collected.add(parsed);
        }
      }

      pageToken = jsonMap['nextPageToken'] as String?;
      nextSyncToken = jsonMap['nextSyncToken'] as String? ?? nextSyncToken;
      if (pageToken == null || pageToken.isEmpty) break;
    }

    return GoogleCalendarEventsDeltaPage(
      items: collected,
      nextSyncToken: nextSyncToken,
      usedIncrementalSyncToken: usingIncremental,
    );
  }

  /// `POST /calendars/{calendarId}/events`
  Future<({String googleEventId, String? etag})> insertEvent({
    required String accessToken,
    required String googleCalendarId,
    required CalendarEventEntity event,
  }) async {
    final encodedCalId = Uri.encodeComponent(googleCalendarId);
    final resp = await _httpClient.post(
      Uri.parse('$baseUrl/calendars/$encodedCalId/events'),
      headers: _headers(accessToken),
      body: jsonEncode(_toGoogleEventPayload(event)),
    );
    await _invalidateIfUnauthorized(resp.statusCode, accessToken);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AppException(
        code: 'GCAL_INSERT_EVENT_ERROR',
        message: 'Không thể đẩy sự kiện mới lên Google Calendar (HTTP ${resp.statusCode}).',
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (
      googleEventId: (data['id'] as String?) ?? '',
      etag: data['etag'] as String?,
    );
  }

  /// `PATCH /calendars/{calendarId}/events/{eventId}`
  Future<({String googleEventId, String? etag})> patchEvent({
    required String accessToken,
    required String googleCalendarId,
    required String googleEventId,
    required CalendarEventEntity event,
  }) async {
    final encodedCalId = Uri.encodeComponent(googleCalendarId);
    final encodedEvId = Uri.encodeComponent(googleEventId);
    final resp = await _httpClient.patch(
      Uri.parse('$baseUrl/calendars/$encodedCalId/events/$encodedEvId'),
      headers: _headers(accessToken),
      body: jsonEncode(_toGoogleEventPayload(event)),
    );
    await _invalidateIfUnauthorized(resp.statusCode, accessToken);
    if (resp.statusCode == 404 || resp.statusCode == 410) {
      // Event was removed remotely -> re-insert cleanly
      return insertEvent(
        accessToken: accessToken,
        googleCalendarId: googleCalendarId,
        event: event,
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AppException(
        code: 'GCAL_PATCH_EVENT_ERROR',
        message: 'Không thể cập nhật sự kiện trên Google Calendar (HTTP ${resp.statusCode}).',
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (
      googleEventId: (data['id'] as String?) ?? googleEventId,
      etag: data['etag'] as String?,
    );
  }

  /// `DELETE /calendars/{calendarId}/events/{eventId}`
  Future<void> deleteEvent({
    required String accessToken,
    required String googleCalendarId,
    required String googleEventId,
  }) async {
    final encodedCalId = Uri.encodeComponent(googleCalendarId);
    final encodedEvId = Uri.encodeComponent(googleEventId);
    final resp = await _httpClient.delete(
      Uri.parse('$baseUrl/calendars/$encodedCalId/events/$encodedEvId'),
      headers: _headers(accessToken),
    );
    await _invalidateIfUnauthorized(resp.statusCode, accessToken);
    if (resp.statusCode != 204 &&
        resp.statusCode != 200 &&
        resp.statusCode != 404 &&
        resp.statusCode != 410) {
      throw AppException(
        code: 'GCAL_DELETE_EVENT_ERROR',
        message: 'Không thể xóa sự kiện trên Google Calendar (HTTP ${resp.statusCode}).',
      );
    }
  }

  static Map<String, dynamic> _toGoogleEventPayload(CalendarEventEntity ev) {
    final rrule = ev.recurrence.toRruleString();
    final Map<String, dynamic> startObj;
    final Map<String, dynamic> endObj;

    if (ev.isAllDay) {
      final startDay = DateTime(ev.startsAt.year, ev.startsAt.month, ev.startsAt.day);
      var endDay = DateTime(ev.endsAt.year, ev.endsAt.month, ev.endsAt.day);
      if (!endDay.isAfter(startDay)) {
        endDay = startDay.add(const Duration(days: 1));
      }
      startObj = <String, dynamic>{'date': _formatYmd(startDay)};
      endObj = <String, dynamic>{'date': _formatYmd(endDay)};
    } else {
      startObj = <String, dynamic>{
        'dateTime': ev.startsAt.toUtc().toIso8601String(),
        'timeZone': ev.timeZone,
      };
      endObj = <String, dynamic>{
        'dateTime': ev.endsAt.toUtc().toIso8601String(),
        'timeZone': ev.timeZone,
      };
    }

    return <String, dynamic>{
      'summary': ev.title,
      if (ev.description != null) 'description': ev.description,
      if (ev.location != null) 'location': ev.location,
      'start': startObj,
      'end': endObj,
      'recurrence': rrule != null ? <String>[rrule] : <String>[],
      'reminders': <String, dynamic>{
        'useDefault': false,
        'overrides': <Map<String, dynamic>>[
          if (ev.reminderMinutesBefore > 0)
            <String, dynamic>{
              'method': 'popup',
              'minutes': ev.reminderMinutesBefore,
            },
        ],
      },
    };
  }

  static GoogleCalendarRemoteItem? _parseRemoteEvent(Map<String, dynamic> raw) {
    final gId = (raw['id'] as String?) ?? '';
    if (gId.isEmpty) return null;
    final status = (raw['status'] as String?) ?? 'confirmed';
    final updatedAt = DateTime.tryParse((raw['updated'] ?? '').toString())?.toLocal() ??
        DateTime.now();

    if (status == 'cancelled') {
      final now = DateTime.now();
      return GoogleCalendarRemoteItem(
        googleEventId: gId,
        status: 'cancelled',
        etag: raw['etag'] as String?,
        summary: '',
        startsAt: now,
        endsAt: now,
        isAllDay: false,
        timeZone: 'Asia/Ho_Chi_Minh',
        recurrence: CalendarRecurrenceRule.none,
        reminderMinutesBefore: 30,
        updatedAt: updatedAt,
      );
    }

    final startMap = (raw['start'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final endMap = (raw['end'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final startDateOnly = startMap['date'] as String?;
    final endDateOnly = endMap['date'] as String?;

    final isAllDay = startDateOnly != null && startDateOnly.isNotEmpty;
    DateTime startsAt;
    DateTime endsAt;

    if (isAllDay) {
      startsAt = DateTime.tryParse(startDateOnly)?.toLocal() ?? DateTime.now();
      final parsedEnd = endDateOnly != null ? DateTime.tryParse(endDateOnly)?.toLocal() : null;
      endsAt = parsedEnd != null && parsedEnd.isAfter(startsAt)
          ? parsedEnd.subtract(const Duration(minutes: 1))
          : startsAt.add(const Duration(hours: 23, minutes: 59));
    } else {
      startsAt = DateTime.tryParse((startMap['dateTime'] ?? '').toString())?.toLocal() ??
          DateTime.now();
      endsAt = DateTime.tryParse((endMap['dateTime'] ?? '').toString())?.toLocal() ??
          startsAt.add(const Duration(hours: 1));
    }

    CalendarRecurrenceRule recurrence = CalendarRecurrenceRule.none;
    final rawRecurrence = raw['recurrence'];
    if (rawRecurrence is Iterable) {
      for (final line in rawRecurrence) {
        final s = line.toString();
        if (s.toUpperCase().startsWith('RRULE:')) {
          recurrence = CalendarRecurrenceRule.fromRruleString(s);
          break;
        }
      }
    }

    var reminderMinutes = 30;
    final remindersMap = raw['reminders'];
    if (remindersMap is Map<String, dynamic>) {
      final overrides = remindersMap['overrides'];
      if (overrides is Iterable && overrides.isNotEmpty) {
        final first = overrides.first;
        if (first is Map<String, dynamic> && first['minutes'] is num) {
          reminderMinutes = (first['minutes'] as num).toInt();
        }
      }
    }

    return GoogleCalendarRemoteItem(
      googleEventId: gId,
      status: status,
      etag: raw['etag'] as String?,
      summary: (raw['summary'] as String?)?.trim().isNotEmpty == true
          ? (raw['summary'] as String).trim()
          : '(Sự kiện không tiêu đề)',
      description: raw['description'] as String?,
      location: raw['location'] as String?,
      startsAt: startsAt,
      endsAt: endsAt,
      isAllDay: isAllDay,
      timeZone: (startMap['timeZone'] as String?) ?? 'Asia/Ho_Chi_Minh',
      recurrence: recurrence,
      reminderMinutesBefore: reminderMinutes,
      updatedAt: updatedAt,
    );
  }

  static String _formatYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String _sanitizeDocId(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return clean.isEmpty ? 'gcal_custom' : clean;
  }
}
