import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/services/native_alarm_scheduler_bridge.dart';
import '../../../../core/services/native_device_calendar_bridge.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../domain/entities/calendar_entities.dart';
import '../../domain/repositories/calendar_repository.dart';
import '../datasources/google_calendar_api_datasource.dart';

class CalendarRemoteDataSource {
  final FirebaseFirestore _firestore;
  final GoogleCalendarApiDataSource? _googleApi;
  final NativeDeviceCalendarBridge _deviceCalendar;
  static const Uuid _uuid = Uuid();

  CalendarRemoteDataSource(
    this._firestore, {
    GoogleCalendarApiDataSource? googleApi,
    NativeDeviceCalendarBridge? deviceCalendar,
  }) : _googleApi = googleApi,
       _deviceCalendar = deviceCalendar ?? NativeDeviceCalendarBridge.instance;

  bool get isGoogleAuthorized => _googleApi?.hasAuthorizedToken ?? false;

  static String googleEventCompositeKey(
    String? googleCalendarId,
    String googleEventId,
  ) {
    final calKey = (googleCalendarId == null || googleCalendarId.trim().isEmpty)
        ? 'primary'
        : googleCalendarId.trim();
    return '$calKey::${googleEventId.trim()}';
  }

  static String googleEventDocId(
    String? googleCalendarId,
    String googleEventId,
  ) {
    final calKey = (googleCalendarId == null || googleCalendarId.trim().isEmpty)
        ? 'primary'
        : googleCalendarId.trim();
    final cleanEv = googleEventId.trim();
    if (calKey == 'primary') {
      return 'gcal_$cleanEv';
    }
    final safeCal = calKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'gcal_${safeCal}_$cleanEv';
  }

  ManagedCalendarEntity _mapCalendarDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String ownerId,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final syncedTs = d['lastSyncedAt'];
    final sourceStr =
        (d['source'] as String?) ?? CalendarProviderSource.lifeOsPrivate.name;
    final source = CalendarProviderSource.values.firstWhere(
      (e) => e.name == sourceStr,
      orElse: () => CalendarProviderSource.lifeOsPrivate,
    );
    return ManagedCalendarEntity(
      id: (d['id'] as String?) ?? doc.id,
      ownerId: (d['ownerId'] as String?) ?? ownerId,
      summary: (d['summary'] as String?) ?? 'Lịch Cá nhân',
      description: d['description'] as String?,
      timeZone: (d['timeZone'] as String?) ?? 'Asia/Ho_Chi_Minh',
      colorHex: (d['colorHex'] as String?) ?? '#0B7A2A',
      isPrimary: (d['isPrimary'] as bool?) ?? (doc.id == 'primary'),
      isSelected: (d['isSelected'] as bool?) ?? true,
      isReadOnly: (d['isReadOnly'] as bool?) ?? false,
      source: source,
      googleCalendarId: d['googleCalendarId'] as String?,
      googleSyncToken: d['googleSyncToken'] as String?,
      deviceCalendarId: (d['deviceCalendarId'] as num?)?.toInt(),
      lastSyncedAt: syncedTs is Timestamp ? syncedTs.toDate() : null,
    );
  }

  Map<String, dynamic> _calendarToFirestore(ManagedCalendarEntity cal) {
    return <String, dynamic>{
      'id': cal.id,
      'ownerId': cal.ownerId,
      'summary': cal.summary,
      'description': cal.description,
      'timeZone': cal.timeZone,
      'colorHex': cal.colorHex,
      'isPrimary': cal.isPrimary,
      'isSelected': cal.isSelected,
      'isReadOnly': cal.isReadOnly,
      'source': cal.source.name,
      'googleCalendarId': cal.googleCalendarId,
      'googleSyncToken': cal.googleSyncToken,
      if (cal.deviceCalendarId != null)
        'deviceCalendarId': cal.deviceCalendarId,
      if (cal.lastSyncedAt != null)
        'lastSyncedAt': Timestamp.fromDate(cal.lastSyncedAt!),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
  }

  Stream<List<ManagedCalendarEntity>> watchCalendars(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('calendars')
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => _mapCalendarDoc(d, userId))
              .toList();
          final hasPrimary = list.any((c) => c.id == 'primary' || c.isPrimary);
          if (!hasPrimary) {
            list.insert(
              0,
              ManagedCalendarEntity(
                id: 'primary',
                ownerId: userId,
                summary: 'Lịch Cá nhân Chính',
                colorHex: '#0B7A2A',
                isPrimary: true,
                isSelected: true,
                source: CalendarProviderSource.lifeOsPrivate,
                googleCalendarId: 'primary',
              ),
            );
          }
          list.sort((a, b) {
            if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
            return a.summary.compareTo(b.summary);
          });
          return list;
        });
  }

  Future<ManagedCalendarEntity> createCalendar({
    required String userId,
    required String summary,
    String? description,
    String colorHex = '#0B7A2A',
    bool createOnGoogle = false,
  }) async {
    ManagedCalendarEntity entity;
    if (createOnGoogle && _googleApi != null) {
      final token = await _googleApi.acquireAccessToken(interactive: true);
      entity = await _googleApi.createSecondaryCalendar(
        accessToken: token,
        ownerId: userId,
        summary: summary,
        description: description,
        colorHex: colorHex,
      );
    } else {
      final id = 'cal_${_uuid.v4().substring(0, 8)}';
      entity = ManagedCalendarEntity(
        id: id,
        ownerId: userId,
        summary: summary,
        description: description,
        colorHex: colorHex,
        isPrimary: false,
        isSelected: true,
        source: CalendarProviderSource.lifeOsPrivate,
      );
    }

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('calendars')
        .doc(entity.id)
        .set(_calendarToFirestore(entity), SetOptions(merge: true));
    return entity;
  }

  Future<ManagedCalendarEntity> updateCalendar({
    required String userId,
    required ManagedCalendarEntity calendar,
  }) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('calendars')
        .doc(calendar.id)
        .set(_calendarToFirestore(calendar), SetOptions(merge: true));
    return calendar;
  }

  static const int maxDeleteBatchOps = 400;

  static bool _isRemoteAlreadyDeletedError(Object error) {
    if (error is AppException) {
      final upperCode = error.code.toUpperCase();
      if (upperCode.contains('404') ||
          upperCode.contains('410') ||
          upperCode.contains('NOT_FOUND')) {
        return true;
      }
      return RegExp(r'\b(?:404|410)\b').hasMatch(error.message);
    }
    return RegExp(r'\b(?:404|410)\b').hasMatch(error.toString());
  }

  /// Disconnects a calendar and its linked private events locally without
  /// deleting the remote Google Calendar.
  Future<void> disconnectCalendarLocally({
    required String userId,
    required ManagedCalendarEntity calendar,
  }) {
    return deleteCalendar(
      userId: userId,
      calendar: calendar,
      disconnectLocalOnly: true,
    );
  }

  Future<void> deleteCalendar({
    required String userId,
    required ManagedCalendarEntity calendar,
    bool disconnectLocalOnly = false,
  }) async {
    if (calendar.isPrimary || calendar.id == 'primary') {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Không thể xóa bộ lịch chính mặc định.',
      );
    }

    final userRef = _firestore.collection('users').doc(userId);
    final calDocRef = userRef.collection('calendars').doc(calendar.id);

    // F17 / CAL-01: Never wipe local calendar & events silently if Google remote deletion fails!
    // Treat HTTP 404 / 410 as idempotent already-deleted success so retries clean up ghost calendars.
    if (!disconnectLocalOnly &&
        calendar.googleCalendarId != null &&
        calendar.googleCalendarId!.isNotEmpty) {
      if (_googleApi == null) {
        await calDocRef.set({
          'pendingRemoteDelete': true,
          'lastSyncError': 'Chưa cấu hình dịch vụ Google Calendar.',
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        }, SetOptions(merge: true));
        throw const AppException(
          code: 'CALENDAR_SYNC_UNAVAILABLE',
          message:
              'Không thể kết nối Google Calendar lúc này. Đã giữ an toàn sự kiện trên máy và đánh dấu chờ xóa.',
        );
      }
      try {
        final token = await _googleApi.acquireAccessToken(interactive: false);
        await _googleApi.deleteSecondaryCalendar(
          accessToken: token,
          googleCalendarId: calendar.googleCalendarId!,
        );
      } catch (e) {
        if (!_isRemoteAlreadyDeletedError(e)) {
          await calDocRef.set({
            'pendingRemoteDelete': true,
            'lastSyncError': e.toString(),
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          }, SetOptions(merge: true));
          throw const AppException(
            code: 'CALENDAR_REMOTE_DELETE_FAILED',
            message:
                'Xóa trên Google Calendar chưa thành công (mất mạng hoặc hết phiên OAuth). Dữ liệu cục bộ được giữ nguyên để tránh mất lịch.',
          );
        }
      }
    }

    final linkedEvents = await userRef
        .collection('private_events')
        .where('calendarId', isEqualTo: calendar.id)
        .get();
    final refsToDelete = <DocumentReference<Map<String, dynamic>>>[
      for (final evDoc in linkedEvents.docs) evDoc.reference,
      calDocRef,
    ];

    // CAL-01: Chunk Firestore batch commits into <= 400 writes (never exceeding 500-op limit).
    for (
      var start = 0;
      start < refsToDelete.length;
      start += maxDeleteBatchOps
    ) {
      final end = (start + maxDeleteBatchOps < refsToDelete.length)
          ? start + maxDeleteBatchOps
          : refsToDelete.length;
      final batch = _firestore.batch();
      for (var i = start; i < end; i++) {
        batch.delete(refsToDelete[i]);
      }
      await batch.commit();
    }
  }

  CalendarEventEntity _mapEvent(
    DocumentSnapshot<Map<String, dynamic>> doc,
    CalendarEventVisibility visibility,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final sTs = d['startsAt'];
    final eTs = d['endsAt'];
    final uTs = d['updatedAt'];
    final syncStr =
        (d['syncStatus'] as String?) ?? CalendarSyncStatus.localOnly.name;
    final syncStatus = CalendarSyncStatus.values.firstWhere(
      (s) => s.name == syncStr,
      orElse: () => CalendarSyncStatus.localOnly,
    );

    return CalendarEventEntity(
      id: (d['id'] as String?) ?? doc.id,
      calendarId: (d['calendarId'] as String?) ?? 'primary',
      ownerId: (d['ownerId'] as String?) ?? '',
      ownerName: (d['ownerName'] as String?) ?? 'Cá nhân',
      familyId: d['familyId'] as String?,
      visibility: visibility,
      title: (d['title'] as String?) ?? '',
      description: d['description'] as String?,
      location: d['location'] as String?,
      startsAt: sTs is Timestamp ? sTs.toDate() : DateTime.now(),
      endsAt: eTs is Timestamp ? eTs.toDate() : DateTime.now(),
      isAllDay: (d['isAllDay'] as bool?) ?? false,
      timeZone: (d['timeZone'] as String?) ?? 'Asia/Ho_Chi_Minh',
      colorHex: d['colorHex'] as String?,
      reminderMinutesBefore:
          (d['reminderMinutesBefore'] as num?)?.toInt() ?? 30,
      recurrence: CalendarRecurrenceRule.fromRruleString(d['rrule'] as String?),
      googleEventId: d['googleEventId'] as String?,
      googleCalendarId: d['googleCalendarId'] as String?,
      googleEtag: d['googleEtag'] as String?,
      deviceEventId: (d['deviceEventId'] as num?)?.toInt(),
      deviceCalendarId: (d['deviceCalendarId'] as num?)?.toInt(),
      syncStatus: syncStatus,
      updatedAt: uTs is Timestamp ? uTs.toDate() : null,
    );
  }

  Map<String, dynamic> _eventToFirestore(
    CalendarEventEntity ev, {
    DateTime? createdAt,
  }) {
    final now = DateTime.now();
    return <String, dynamic>{
      'id': ev.id,
      'calendarId': ev.calendarId,
      'ownerId': ev.ownerId,
      'ownerName': ev.ownerName,
      'familyId': ev.familyId,
      'visibility': ev.visibility.name,
      'title': ev.title,
      'description': ev.description,
      'location': ev.location,
      'startsAt': Timestamp.fromDate(ev.startsAt),
      'endsAt': Timestamp.fromDate(ev.endsAt),
      'isAllDay': ev.isAllDay,
      'timeZone': ev.timeZone,
      'colorHex': ev.colorHex,
      'reminderMinutesBefore': ev.reminderMinutesBefore,
      'rrule': ev.recurrence.toRruleString(),
      'googleEventId': ev.googleEventId,
      'googleCalendarId': ev.googleCalendarId,
      'googleEtag': ev.googleEtag,
      if (ev.deviceEventId != null) 'deviceEventId': ev.deviceEventId,
      if (ev.deviceCalendarId != null) 'deviceCalendarId': ev.deviceCalendarId,
      'syncStatus': ev.syncStatus.name,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(ev.updatedAt ?? now),
    };
  }

  Stream<List<CalendarEventEntity>> watchEvents({
    required String userId,
    String? familyId,
  }) {
    final privateStream = _firestore
        .collection('users')
        .doc(userId)
        .collection('private_events')
        .orderBy('startsAt')
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => _mapEvent(d, CalendarEventVisibility.privateEvent))
              .where((ev) => ev.syncStatus != CalendarSyncStatus.pendingDelete)
              .toList(),
        );

    if (familyId == null || familyId.isEmpty) {
      return privateStream;
    }

    final sharedStream = _firestore
        .collection('families')
        .doc(familyId)
        .collection('shared_events')
        .orderBy('startsAt')
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => _mapEvent(d, CalendarEventVisibility.sharedEvent))
              .where((ev) => ev.syncStatus != CalendarSyncStatus.pendingDelete)
              .toList(),
        );

    return StreamCombiner.combine2(privateStream, sharedStream, (priv, shared) {
      final combined = <CalendarEventEntity>[...priv, ...shared];
      combined.sort((a, b) => a.startsAt.compareTo(b.startsAt));
      return combined;
    });
  }

  Stream<List<BusySlotEntity>> watchFamilyBusySlots(String familyId) {
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('availability')
        .orderBy('startsAt')
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final d = doc.data();
            final sTs = d['startsAt'];
            final eTs = d['endsAt'];
            return BusySlotEntity(
              id: doc.id,
              ownerId: (d['ownerId'] as String?) ?? '',
              ownerName: (d['ownerName'] as String?) ?? 'Thành viên',
              startsAt: sTs is Timestamp ? sTs.toDate() : DateTime.now(),
              endsAt: eTs is Timestamp ? eTs.toDate() : DateTime.now(),
            );
          }).toList();
        });
  }

  Future<String> _resolveTargetGoogleCalendarId(
    String userId,
    String calendarId,
  ) async {
    if (calendarId == 'primary' || calendarId.isEmpty) return 'primary';
    final snap = await _firestore
        .collection('users')
        .doc(userId)
        .collection('calendars')
        .doc(calendarId)
        .get();
    final gId = snap.data()?['googleCalendarId'] as String?;
    return (gId != null && gId.isNotEmpty) ? gId : 'primary';
  }

  Future<int?> _resolveTargetDeviceCalendarId(
    String userId,
    String calendarId,
  ) async {
    if (calendarId.startsWith('devcal_')) {
      return int.tryParse(calendarId.substring(7));
    }
    if (calendarId.isEmpty) return null;
    final snap = await _firestore
        .collection('users')
        .doc(userId)
        .collection('calendars')
        .doc(calendarId)
        .get();
    return (snap.data()?['deviceCalendarId'] as num?)?.toInt();
  }

  Future<CalendarEventEntity> createEvent({
    required String userId,
    required String userName,
    String calendarId = 'primary',
    String? familyId,
    required CalendarEventVisibility visibility,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool isAllDay = false,
    String? colorHex,
    int reminderMinutesBefore = 30,
    CalendarRecurrenceRule recurrence = CalendarRecurrenceRule.none,
    required bool publishBusySlot,
    bool syncToGoogle = false,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    var draft = CalendarEventEntity(
      id: id,
      calendarId: calendarId,
      ownerId: userId,
      ownerName: userName,
      familyId: familyId,
      visibility: visibility,
      title: title,
      description: description,
      location: location,
      startsAt: startsAt,
      endsAt: endsAt,
      isAllDay: isAllDay,
      colorHex: colorHex,
      reminderMinutesBefore: reminderMinutesBefore,
      recurrence: recurrence,
      syncStatus: syncToGoogle
          ? CalendarSyncStatus.pendingUpload
          : CalendarSyncStatus.localOnly,
      updatedAt: now,
    );

    if (syncToGoogle && visibility == CalendarEventVisibility.privateEvent) {
      var syncedExternally = false;

      // 1. Write directly to Android / OS System Calendar (`CalendarContract`) if permitted
      if (await _deviceCalendar.hasPermission()) {
        final preferredDevCalId = await _resolveTargetDeviceCalendarId(
          userId,
          calendarId,
        );
        final savedDevEvId = await _deviceCalendar.upsertEvent(
          deviceCalendarId: preferredDevCalId,
          title: draft.title,
          description: draft.description,
          location: draft.location,
          startsAt: draft.startsAt,
          endsAt: draft.endsAt,
          isAllDay: draft.isAllDay,
          timeZone: draft.timeZone,
          rrule: draft.recurrence.toRruleString(),
          reminderMinutesBefore: draft.reminderMinutesBefore,
        );
        if (savedDevEvId != null && savedDevEvId > 0) {
          draft = draft.copyWith(
            deviceEventId: savedDevEvId,
            deviceCalendarId: preferredDevCalId,
            syncStatus: CalendarSyncStatus.synced,
          );
          syncedExternally = true;
        }
      }

      // 2. Also push to Google Calendar REST API v3 if authorized (and not already synced via device Google account)
      if (!syncedExternally && _googleApi != null) {
        try {
          final token = await _googleApi.acquireAccessToken(interactive: false);
          final targetGCalId = await _resolveTargetGoogleCalendarId(
            userId,
            calendarId,
          );
          final remote = await _googleApi.insertEvent(
            accessToken: token,
            googleCalendarId: targetGCalId,
            event: draft,
          );
          draft = draft.copyWith(
            googleCalendarId: targetGCalId,
            googleEventId: remote.googleEventId,
            googleEtag: remote.etag,
            syncStatus: CalendarSyncStatus.synced,
          );
          syncedExternally = true;
        } catch (_) {
          draft = draft.copyWith(syncStatus: CalendarSyncStatus.pendingUpload);
        }
      }
    }

    final batch = _firestore.batch();
    final docRef = visibility == CalendarEventVisibility.privateEvent
        ? _firestore
              .collection('users')
              .doc(userId)
              .collection('private_events')
              .doc(id)
        : _firestore
              .collection('families')
              .doc(familyId)
              .collection('shared_events')
              .doc(id);

    batch.set(docRef, _eventToFirestore(draft, createdAt: now));

    // Opt-in availability only publishes redacted busy window (NEVER title or description!)
    if (visibility == CalendarEventVisibility.privateEvent &&
        publishBusySlot &&
        familyId != null &&
        familyId.isNotEmpty) {
      final slotRef = _firestore
          .collection('families')
          .doc(familyId)
          .collection('availability')
          .doc(id);
      batch.set(slotRef, {
        'id': id,
        'ownerId': userId,
        'ownerName': userName,
        'startsAt': Timestamp.fromDate(startsAt),
        'endsAt': Timestamp.fromDate(endsAt),
      });
    }

    await batch.commit();
    final snap = await docRef.get();
    return _mapEvent(snap, visibility);
  }

  Future<CalendarEventEntity> updateEvent({
    required String userId,
    required String userName,
    required CalendarEventEntity existingEvent,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool? isAllDay,
    String? calendarId,
    String? colorHex,
    int? reminderMinutesBefore,
    CalendarRecurrenceRule? recurrence,
    bool publishBusySlot = false,
    bool syncToGoogle = false,
  }) async {
    final now = DateTime.now();
    final shouldSyncExternal =
        syncToGoogle ||
        existingEvent.isLinkedWithGoogle ||
        existingEvent.isLinkedWithDeviceCalendar;

    var updated = existingEvent.copyWith(
      calendarId: calendarId ?? existingEvent.calendarId,
      title: title,
      description: description,
      location: location,
      startsAt: startsAt,
      endsAt: endsAt,
      isAllDay: isAllDay ?? existingEvent.isAllDay,
      colorHex: colorHex ?? existingEvent.colorHex,
      reminderMinutesBefore:
          reminderMinutesBefore ?? existingEvent.reminderMinutesBefore,
      recurrence: recurrence ?? existingEvent.recurrence,
      syncStatus: shouldSyncExternal
          ? CalendarSyncStatus.pendingUpload
          : existingEvent.syncStatus,
      updatedAt: now,
    );

    if (shouldSyncExternal &&
        updated.visibility == CalendarEventVisibility.privateEvent) {
      var syncedExternally = false;

      if (await _deviceCalendar.hasPermission()) {
        final preferredDevCalId =
            updated.deviceCalendarId ??
            await _resolveTargetDeviceCalendarId(userId, updated.calendarId);
        final savedDevEvId = await _deviceCalendar.upsertEvent(
          deviceEventId: updated.deviceEventId,
          deviceCalendarId: preferredDevCalId,
          title: updated.title,
          description: updated.description,
          location: updated.location,
          startsAt: updated.startsAt,
          endsAt: updated.endsAt,
          isAllDay: updated.isAllDay,
          timeZone: updated.timeZone,
          rrule: updated.recurrence.toRruleString(),
          reminderMinutesBefore: updated.reminderMinutesBefore,
        );
        if (savedDevEvId != null && savedDevEvId > 0) {
          updated = updated.copyWith(
            deviceEventId: savedDevEvId,
            deviceCalendarId: preferredDevCalId,
            syncStatus: CalendarSyncStatus.synced,
          );
          syncedExternally = true;
        }
      }

      if (!syncedExternally && _googleApi != null) {
        try {
          final token = await _googleApi.acquireAccessToken(interactive: false);
          final targetGCalId =
              updated.googleCalendarId ??
              await _resolveTargetGoogleCalendarId(userId, updated.calendarId);
          final remote = updated.isLinkedWithGoogle
              ? await _googleApi.patchEvent(
                  accessToken: token,
                  googleCalendarId: targetGCalId,
                  googleEventId: updated.googleEventId!,
                  event: updated,
                )
              : await _googleApi.insertEvent(
                  accessToken: token,
                  googleCalendarId: targetGCalId,
                  event: updated,
                );
          updated = updated.copyWith(
            googleCalendarId: targetGCalId,
            googleEventId: remote.googleEventId,
            googleEtag: remote.etag,
            syncStatus: CalendarSyncStatus.synced,
          );
        } catch (_) {
          updated = updated.copyWith(
            syncStatus: CalendarSyncStatus.pendingUpload,
          );
        }
      }
    }

    final batch = _firestore.batch();
    final docRef = updated.visibility == CalendarEventVisibility.privateEvent
        ? _firestore
              .collection('users')
              .doc(userId)
              .collection('private_events')
              .doc(updated.id)
        : _firestore
              .collection('families')
              .doc(updated.familyId)
              .collection('shared_events')
              .doc(updated.id);

    batch.set(docRef, _eventToFirestore(updated), SetOptions(merge: true));

    if (updated.visibility == CalendarEventVisibility.privateEvent &&
        updated.familyId != null &&
        updated.familyId!.isNotEmpty) {
      final slotRef = _firestore
          .collection('families')
          .doc(updated.familyId)
          .collection('availability')
          .doc(updated.id);
      if (publishBusySlot) {
        batch.set(slotRef, {
          'id': updated.id,
          'ownerId': userId,
          'ownerName': userName,
          'startsAt': Timestamp.fromDate(startsAt),
          'endsAt': Timestamp.fromDate(endsAt),
        });
      } else {
        // Immediately revoke previously published Busy/Free slot when user disables sharing!
        batch.delete(slotRef);
      }
    }

    await batch.commit();
    final snap = await docRef.get();
    return _mapEvent(snap, updated.visibility);
  }

  Future<void> deleteEvent({
    required String userId,
    String? familyId,
    required CalendarEventVisibility visibility,
    required String eventId,
    String? googleCalendarId,
    String? googleEventId,
  }) async {
    await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(eventId);
    if (visibility == CalendarEventVisibility.privateEvent) {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('private_events')
          .doc(eventId);
      final snap = await docRef.get();
      final devEvId = (snap.data()?['deviceEventId'] as num?)?.toInt();
      if (devEvId != null &&
          devEvId > 0 &&
          await _deviceCalendar.hasPermission()) {
        await _deviceCalendar.deleteEvent(devEvId);
      }

      final gEvId = googleEventId ?? (snap.data()?['googleEventId'] as String?);
      final gCalId =
          googleCalendarId ??
          (snap.data()?['googleCalendarId'] as String?) ??
          'primary';

      if (gEvId != null && gEvId.isNotEmpty && _googleApi != null) {
        try {
          final token = await _googleApi.acquireAccessToken(interactive: false);
          await _googleApi.deleteEvent(
            accessToken: token,
            googleCalendarId: gCalId,
            googleEventId: gEvId,
          );
        } catch (_) {
          // Offline safety: mark tombstone so next sync deletes remotely on Google Calendar,
          // and immediately clear the family busy-slot so ghost availability never lingers!
          final offlineBatch = _firestore.batch();
          offlineBatch.set(docRef, {
            'syncStatus': CalendarSyncStatus.pendingDelete.name,
            if (familyId != null && familyId.isNotEmpty)
              'pendingDeleteFamilyId': familyId,
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          }, SetOptions(merge: true));
          if (familyId != null && familyId.isNotEmpty) {
            offlineBatch.delete(
              _firestore
                  .collection('families')
                  .doc(familyId)
                  .collection('availability')
                  .doc(eventId),
            );
          }
          await offlineBatch.commit();
          return;
        }
      }

      final batch = _firestore.batch();
      batch.delete(docRef);
      if (familyId != null && familyId.isNotEmpty) {
        batch.delete(
          _firestore
              .collection('families')
              .doc(familyId)
              .collection('availability')
              .doc(eventId),
        );
      }
      await batch.commit();
      return;
    }

    if (familyId != null && familyId.isNotEmpty) {
      await _firestore
          .collection('families')
          .doc(familyId)
          .collection('shared_events')
          .doc(eventId)
          .delete();
    }
  }

  /// Real Two-Way Calendar Synchronization:
  /// - Engine A: Native OS System Calendar (`CalendarContract` — Google Calendar app, Samsung Calendar,
  ///   Outlook, iCloud/CalDAV, Holidays on phone) with zero OAuth SHA-1 friction!
  /// - Engine B: Official Google Calendar REST API v3 (`CalendarList` + `syncToken` incremental delta)
  ///   when OAuth / manual access token is available, automatically deduplicating by `googleEventId` / `syncId`.
  Future<GoogleCalendarSyncReport> syncWithGoogleCalendar({
    required String userId,
    required String userName,
    bool interactivePromptIfNeeded = true,
    String? manualAccessTokenOverride,
  }) async {
    final userRef = _firestore.collection('users').doc(userId);
    final calendarsCol = userRef.collection('calendars');
    final eventsCol = userRef.collection('private_events');
    final now = DateTime.now();

    var totalCalendarsSynced = 0;
    var pushedUpserted = 0;
    var pushedDeleted = 0;
    var pulledUpserted = 0;
    var pulledDeleted = 0;
    var usedIncremental = false;
    var deviceSyncedOk = false;
    var googleSyncedOk = false;

    // =========================================================================
    // ENGINE A: Native OS Device Calendar (`CalendarContract`) 2-Way Sync
    // =========================================================================
    final forceManualGoogleOnly =
        manualAccessTokenOverride != null &&
        manualAccessTokenOverride.trim().isNotEmpty;

    if (!forceManualGoogleOnly && _deviceCalendar.isSupportedPlatform) {
      var hasPerm = await _deviceCalendar.hasPermission();
      if (!hasPerm && interactivePromptIfNeeded) {
        hasPerm = await _deviceCalendar.requestPermission();
      }

      if (hasPerm) {
        final existingCalDocs = await calendarsCol.get();
        final existingCalById = <String, ManagedCalendarEntity>{
          for (final doc in existingCalDocs.docs)
            doc.id: _mapCalendarDoc(doc, userId),
        };

        final devCalendars = await _deviceCalendar.listCalendars();
        final calBatch = _firestore.batch();
        final activeDevCalIds = <int, String>{};
        final devCalColorById = <int, String>{};
        final seenCanonicalToDocId = <String, String>{};

        // Pre-seed canonical keys from existing Google / LifeOS calendars so Engine A
        // maps identical device calendars directly onto existing canonical IDs instead of duplicating.
        for (final existing in existingCalById.values) {
          if (!existing.id.startsWith('devcal_')) {
            final key = CalendarListDeduplicator.canonicalGroupKey(existing);
            seenCanonicalToDocId.putIfAbsent(key, () => existing.id);
          }
        }

        for (final dc in devCalendars) {
          final tempEntity = ManagedCalendarEntity(
            id: dc.isPrimary ? 'primary' : 'devcal_${dc.deviceCalendarId}',
            ownerId: userId,
            summary: dc.summary,
            description: dc.accountName,
            isPrimary: dc.isPrimary,
            isReadOnly: dc.isReadOnly,
            source: CalendarProviderSource.deviceCalendar,
          );
          final canonicalKey = CalendarListDeduplicator.canonicalGroupKey(
            tempEntity,
          );
          final calDocId = canonicalKey == '__primary__'
              ? 'primary'
              : (seenCanonicalToDocId[canonicalKey] ??
                    'devcal_${dc.deviceCalendarId}');
          seenCanonicalToDocId.putIfAbsent(canonicalKey, () => calDocId);

          final prev = existingCalById[calDocId];
          final merged = ManagedCalendarEntity(
            id: calDocId,
            ownerId: userId,
            summary: prev != null && !prev.id.startsWith('devcal_')
                ? prev.summary
                : dc.summary,
            description: dc.accountName.isNotEmpty
                ? dc.accountName
                : prev?.description,
            timeZone: dc.timeZone,
            colorHex: prev?.colorHex ?? dc.colorHex,
            isPrimary: dc.isPrimary || calDocId == 'primary',
            isSelected: prev?.isSelected ?? true,
            isReadOnly: prev?.isReadOnly ?? dc.isReadOnly,
            source:
                prev != null &&
                    prev.source == CalendarProviderSource.googleCalendar
                ? CalendarProviderSource.googleCalendar
                : CalendarProviderSource.deviceCalendar,
            googleCalendarId: prev?.googleCalendarId,
            googleSyncToken: prev?.googleSyncToken,
            deviceCalendarId: prev?.deviceCalendarId ?? dc.deviceCalendarId,
            lastSyncedAt: now,
          );
          calBatch.set(
            calendarsCol.doc(calDocId),
            _calendarToFirestore(merged),
            SetOptions(merge: true),
          );
          existingCalById[calDocId] = merged;
          if (merged.isSelected) {
            activeDevCalIds[dc.deviceCalendarId] = calDocId;
          }
          devCalColorById[dc.deviceCalendarId] = dc.colorHex;
        }
        await calBatch.commit();

        // Push local pending deletes & localOnly / pendingUpload private events to Device Calendar
        final localDocsSnap = await eventsCol.get();
        final localByDocId = <String, CalendarEventEntity>{};
        final localBySyncId = <String, CalendarEventEntity>{};
        final localByDeviceEventId = <int, CalendarEventEntity>{};

        for (final doc in localDocsSnap.docs) {
          final ev = _mapEvent(doc, CalendarEventVisibility.privateEvent);
          if (ev.syncStatus == CalendarSyncStatus.pendingDelete) {
            if (ev.deviceEventId != null && ev.deviceEventId! > 0) {
              await _deviceCalendar.deleteEvent(ev.deviceEventId!);
              pushedDeleted++;
            }
            if (!ev.isLinkedWithGoogle) {
              await doc.reference.delete();
            }
            continue;
          }

          if (!ev.isLinkedWithDeviceCalendar &&
              !ev.isLinkedWithGoogle &&
              (ev.syncStatus == CalendarSyncStatus.pendingUpload ||
                  ev.syncStatus == CalendarSyncStatus.localOnly)) {
            final targetDevCal = await _resolveTargetDeviceCalendarId(
              userId,
              ev.calendarId,
            );
            final savedId = await _deviceCalendar.upsertEvent(
              deviceCalendarId: targetDevCal,
              title: ev.title,
              description: ev.description,
              location: ev.location,
              startsAt: ev.startsAt,
              endsAt: ev.endsAt,
              isAllDay: ev.isAllDay,
              timeZone: ev.timeZone,
              rrule: ev.recurrence.toRruleString(),
              reminderMinutesBefore: ev.reminderMinutesBefore,
            );
            if (savedId != null && savedId > 0) {
              final syncedEv = ev.copyWith(
                deviceEventId: savedId,
                deviceCalendarId: targetDevCal,
                syncStatus: CalendarSyncStatus.synced,
                updatedAt: now,
              );
              await doc.reference.set(
                _eventToFirestore(syncedEv),
                SetOptions(merge: true),
              );
              localByDocId[syncedEv.id] = syncedEv;
              localByDeviceEventId[savedId] = syncedEv;
              pushedUpserted++;
              continue;
            }
          }

          localByDocId[ev.id] = ev;
          if (ev.googleEventId != null && ev.googleEventId!.isNotEmpty) {
            localBySyncId[ev.googleEventId!] = ev;
          }
          if (ev.deviceEventId != null && ev.deviceEventId! > 0) {
            localByDeviceEventId[ev.deviceEventId!] = ev;
          }
        }

        // Pull all real events in [-90 days, +365 days] from Device Calendar
        final windowStart = now.subtract(const Duration(days: 90));
        final windowEnd = now.add(const Duration(days: 365));
        final devEvents = await _deviceCalendar.listEvents(
          windowStart: windowStart,
          windowEnd: windowEnd,
        );

        final seenDocIds = <String>{};
        var pullBatch = _firestore.batch();
        var opsInBatch = 0;

        Future<void> commitIfNeeded({bool force = false}) async {
          if (opsInBatch >= 400 || (force && opsInBatch > 0)) {
            await pullBatch.commit();
            pullBatch = _firestore.batch();
            opsInBatch = 0;
          }
        }

        for (final item in devEvents) {
          if (activeDevCalIds.isNotEmpty &&
              !activeDevCalIds.containsKey(item.deviceCalendarId)) {
            continue;
          }
          final mappedCalId =
              activeDevCalIds[item.deviceCalendarId] ?? 'primary';

          // Deduplicate with Google-synced events or previously pushed LifeOS events
          final existingBySync =
              (item.syncId != null && item.syncId!.isNotEmpty)
              ? localBySyncId[item.syncId!]
              : null;
          final existingByDevId = !item.instanceKey.contains('_')
              ? localByDeviceEventId[item.deviceEventId]
              : null;
          final fallbackDocId = 'devcal_${item.instanceKey}';
          final matchedLocal =
              existingBySync ?? existingByDevId ?? localByDocId[fallbackDocId];

          final docId = matchedLocal?.id ?? fallbackDocId;
          seenDocIds.add(docId);

          final upserted = CalendarEventEntity(
            id: docId,
            calendarId: mappedCalId,
            ownerId: userId,
            ownerName: userName,
            visibility: CalendarEventVisibility.privateEvent,
            title: item.title,
            description: item.description,
            location: item.location,
            startsAt: item.startsAt,
            endsAt: item.endsAt,
            isAllDay: item.isAllDay,
            timeZone: item.timeZone,
            colorHex: devCalColorById[item.deviceCalendarId] ?? item.colorHex,
            reminderMinutesBefore: matchedLocal?.reminderMinutesBefore ?? 15,
            recurrence: CalendarRecurrenceRule.fromRruleString(item.rrule),
            googleEventId: item.syncId ?? matchedLocal?.googleEventId,
            googleCalendarId: matchedLocal?.googleCalendarId,
            googleEtag: matchedLocal?.googleEtag,
            deviceEventId: item.deviceEventId,
            deviceCalendarId: item.deviceCalendarId,
            syncStatus: CalendarSyncStatus.synced,
            updatedAt: now,
          );

          pullBatch.set(
            eventsCol.doc(docId),
            _eventToFirestore(upserted),
            SetOptions(merge: true),
          );
          opsInBatch++;
          pulledUpserted++;
          await commitIfNeeded();
        }

        // Prune stale `devcal_*` events inside the sync window that were deleted on the phone!
        for (final entry in localByDocId.entries) {
          final existing = entry.value;
          if ((existing.id.startsWith('devcal_') ||
                  existing.isLinkedWithDeviceCalendar) &&
              !seenDocIds.contains(existing.id) &&
              !existing.startsAt.isBefore(windowStart) &&
              !existing.startsAt.isAfter(windowEnd)) {
            pullBatch.delete(eventsCol.doc(existing.id));
            opsInBatch++;
            pulledDeleted++;
            await commitIfNeeded();
          }
        }
        await commitIfNeeded(force: true);

        totalCalendarsSynced = activeDevCalIds.isNotEmpty
            ? activeDevCalIds.length
            : devCalendars.length;
        deviceSyncedOk = true;
      }
    }

    // =========================================================================
    // ENGINE B: Official Google Calendar REST API v3 (`CalendarList` + `syncToken`)
    // =========================================================================
    final api = _googleApi;
    if (api != null) {
      // If Device Calendar already succeeded, try Google REST API silently (`interactive: false`)
      // so we never block or throw OAuth SHA-1 errors when Device Calendar already synced everything!
      final shouldTryGoogle =
          forceManualGoogleOnly || !deviceSyncedOk || api.hasAuthorizedToken;
      if (shouldTryGoogle) {
        try {
          final accessToken = await api.acquireAccessToken(
            interactive: deviceSyncedOk ? false : interactivePromptIfNeeded,
            manualTokenOverride: manualAccessTokenOverride,
          );

          final existingCalDocs = await calendarsCol.get();
          final existingCalById = <String, ManagedCalendarEntity>{
            for (final doc in existingCalDocs.docs)
              doc.id: _mapCalendarDoc(doc, userId),
          };

          final remoteCalendars = await api.listCalendars(
            accessToken: accessToken,
            ownerId: userId,
          );

          final calBatch = _firestore.batch();
          final syncedCalendars = <ManagedCalendarEntity>[];
          for (final rc in remoteCalendars) {
            final rcKey = CalendarListDeduplicator.canonicalGroupKey(rc);
            ManagedCalendarEntity? prev = existingCalById[rc.id];
            final duplicateDevCalIds = <String>[];

            for (final existing in existingCalById.values) {
              if (existing.id == rc.id) continue;
              if (existing.id.startsWith('devcal_') &&
                  CalendarListDeduplicator.canonicalGroupKey(existing) ==
                      rcKey) {
                prev ??= existing;
                duplicateDevCalIds.add(existing.id);
              }
            }

            final merged = rc.copyWith(
              isSelected: prev?.isSelected ?? rc.isSelected,
              googleSyncToken: prev?.googleSyncToken,
              deviceCalendarId: prev?.deviceCalendarId,
              lastSyncedAt: prev?.lastSyncedAt,
            );
            syncedCalendars.add(merged);
            calBatch.set(
              calendarsCol.doc(merged.id),
              _calendarToFirestore(merged),
              SetOptions(merge: true),
            );
            for (final dupId in duplicateDevCalIds) {
              calBatch.delete(calendarsCol.doc(dupId));
            }
          }
          await calBatch.commit();

          final userSnap = await _firestore
              .collection('users')
              .doc(userId)
              .get();
          final activeUserFamilyId =
              (userSnap.data()?['activeFamilyId'] as String?)?.trim();

          final localDocsSnap = await eventsCol.get();
          final localByGoogleCompositeKey = <String, CalendarEventEntity>{};

          for (final doc in localDocsSnap.docs) {
            final rawData = doc.data();
            final ev = _mapEvent(doc, CalendarEventVisibility.privateEvent);
            if (ev.syncStatus == CalendarSyncStatus.pendingDelete) {
              if (ev.isLinkedWithGoogle) {
                await api.deleteEvent(
                  accessToken: accessToken,
                  googleCalendarId: ev.googleCalendarId ?? 'primary',
                  googleEventId: ev.googleEventId!,
                );
                pushedDeleted++;
              }
              final cleanupFamId =
                  (rawData['pendingDeleteFamilyId'] as String?)?.trim() ??
                  ev.familyId ??
                  activeUserFamilyId;
              final delBatch = _firestore.batch();
              delBatch.delete(doc.reference);
              if (cleanupFamId != null && cleanupFamId.isNotEmpty) {
                delBatch.delete(
                  _firestore
                      .collection('families')
                      .doc(cleanupFamId)
                      .collection('availability')
                      .doc(ev.id),
                );
              }
              await delBatch.commit();
              continue;
            }

            if (ev.syncStatus == CalendarSyncStatus.pendingUpload ||
                ev.syncStatus == CalendarSyncStatus.localOnly) {
              final targetGCalId =
                  ev.googleCalendarId ??
                  await _resolveTargetGoogleCalendarId(userId, ev.calendarId);
              final remoteRes = ev.isLinkedWithGoogle
                  ? await api.patchEvent(
                      accessToken: accessToken,
                      googleCalendarId: targetGCalId,
                      googleEventId: ev.googleEventId!,
                      event: ev,
                    )
                  : await api.insertEvent(
                      accessToken: accessToken,
                      googleCalendarId: targetGCalId,
                      event: ev,
                    );
              final syncedEv = ev.copyWith(
                googleCalendarId: targetGCalId,
                googleEventId: remoteRes.googleEventId,
                googleEtag: remoteRes.etag,
                syncStatus: CalendarSyncStatus.synced,
                updatedAt: DateTime.now(),
              );
              await doc.reference.set(
                _eventToFirestore(syncedEv),
                SetOptions(merge: true),
              );
              localByGoogleCompositeKey[googleEventCompositeKey(
                    targetGCalId,
                    remoteRes.googleEventId,
                  )] =
                  syncedEv;
              pushedUpserted++;
            } else if (ev.isLinkedWithGoogle) {
              localByGoogleCompositeKey[googleEventCompositeKey(
                    ev.googleCalendarId,
                    ev.googleEventId!,
                  )] =
                  ev;
            }
          }

          final activeGoogleCals = syncedCalendars
              .where((c) => c.isSelected && c.isGoogleSynced)
              .toList();

          for (final gCal in activeGoogleCals) {
            final gCalId = gCal.googleCalendarId ?? 'primary';
            final deltaPage = await api.listEventsDelta(
              accessToken: accessToken,
              googleCalendarId: gCalId,
              syncToken: gCal.googleSyncToken,
            );
            if (deltaPage.usedIncrementalSyncToken) {
              usedIncremental = true;
            }

            final pullBatch = _firestore.batch();
            for (final remoteEv in deltaPage.items) {
              final matchedLocal =
                  localByGoogleCompositeKey[googleEventCompositeKey(
                    gCalId,
                    remoteEv.googleEventId,
                  )];
              if (remoteEv.isCancelled) {
                if (matchedLocal != null) {
                  pullBatch.delete(eventsCol.doc(matchedLocal.id));
                  final cleanupFamId =
                      matchedLocal.familyId ?? activeUserFamilyId;
                  if (cleanupFamId != null && cleanupFamId.isNotEmpty) {
                    pullBatch.delete(
                      _firestore
                          .collection('families')
                          .doc(cleanupFamId)
                          .collection('availability')
                          .doc(matchedLocal.id),
                    );
                  }
                  pulledDeleted++;
                }
                continue;
              }

              if (matchedLocal != null &&
                  matchedLocal.googleEtag != null &&
                  matchedLocal.googleEtag == remoteEv.etag) {
                continue;
              }

              final docId =
                  matchedLocal?.id ??
                  googleEventDocId(gCalId, remoteEv.googleEventId);
              final upsertedEntity = CalendarEventEntity(
                id: docId,
                calendarId: gCal.id,
                ownerId: userId,
                ownerName: userName,
                visibility: CalendarEventVisibility.privateEvent,
                title: remoteEv.summary,
                description: remoteEv.description,
                location: remoteEv.location,
                startsAt: remoteEv.startsAt,
                endsAt: remoteEv.endsAt,
                isAllDay: remoteEv.isAllDay,
                timeZone: remoteEv.timeZone,
                colorHex: gCal.colorHex,
                reminderMinutesBefore: remoteEv.reminderMinutesBefore,
                recurrence: remoteEv.recurrence,
                googleEventId: remoteEv.googleEventId,
                googleCalendarId: gCalId,
                googleEtag: remoteEv.etag,
                deviceEventId: matchedLocal?.deviceEventId,
                deviceCalendarId: matchedLocal?.deviceCalendarId,
                syncStatus: CalendarSyncStatus.synced,
                updatedAt: remoteEv.updatedAt,
              );

              pullBatch.set(
                eventsCol.doc(docId),
                _eventToFirestore(upsertedEntity),
                SetOptions(merge: true),
              );
              pulledUpserted++;
            }

            final updatedCal = gCal.copyWith(
              googleSyncToken: deltaPage.nextSyncToken ?? gCal.googleSyncToken,
              lastSyncedAt: now,
            );
            pullBatch.set(
              calendarsCol.doc(gCal.id),
              _calendarToFirestore(updatedCal),
              SetOptions(merge: true),
            );
            await pullBatch.commit();
          }

          if (activeGoogleCals.length > totalCalendarsSynced) {
            totalCalendarsSynced = activeGoogleCals.length;
          }
          googleSyncedOk = true;
        } catch (e) {
          if (!deviceSyncedOk) {
            rethrow;
          }
        }
      }
    }

    if (!deviceSyncedOk && !googleSyncedOk) {
      throw const AppException(
        code: 'CALENDAR_PERMISSION_REQUIRED',
        message:
            'Vui lòng cấp quyền truy cập Lịch để đồng bộ các sự kiện thật trên thiết bị của bạn.',
      );
    }

    final sourceLabel = (deviceSyncedOk && googleSyncedOk)
        ? 'Lịch Thiết bị & Google Calendar'
        : (deviceSyncedOk ? 'Lịch trên Thiết bị' : 'Google Calendar');

    return GoogleCalendarSyncReport(
      calendarsSynced: totalCalendarsSynced,
      pulledUpserted: pulledUpserted,
      pulledDeleted: pulledDeleted,
      pushedUpserted: pushedUpserted,
      pushedDeleted: pushedDeleted,
      usedIncrementalSyncToken: usedIncremental,
      syncedAt: now,
      sourceLabel: sourceLabel,
    );
  }
}

class CalendarRepositoryImpl implements CalendarRepository {
  final CalendarRemoteDataSource _remoteDataSource;
  const CalendarRepositoryImpl(this._remoteDataSource);

  @override
  bool get isGoogleCalendarAuthorized => _remoteDataSource.isGoogleAuthorized;

  @override
  Stream<Result<List<ManagedCalendarEntity>>> watchCalendars(String userId) {
    return _remoteDataSource
        .watchCalendars(userId)
        .map<Result<List<ManagedCalendarEntity>>>((items) => Success(items))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<ManagedCalendarEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Future<Result<ManagedCalendarEntity>> createCalendar({
    required String userId,
    required String summary,
    String? description,
    String colorHex = '#0B7A2A',
    bool createOnGoogle = false,
  }) async {
    try {
      final created = await _remoteDataSource.createCalendar(
        userId: userId,
        summary: summary,
        description: description,
        colorHex: colorHex,
        createOnGoogle: createOnGoogle,
      );
      return Success(created);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<ManagedCalendarEntity>> updateCalendar({
    required String userId,
    required ManagedCalendarEntity calendar,
  }) async {
    try {
      final updated = await _remoteDataSource.updateCalendar(
        userId: userId,
        calendar: calendar,
      );
      return Success(updated);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> deleteCalendar({
    required String userId,
    required ManagedCalendarEntity calendar,
  }) async {
    try {
      await _remoteDataSource.deleteCalendar(
        userId: userId,
        calendar: calendar,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  /// Disconnects a Google or local secondary calendar locally without deleting
  /// the remote Google Calendar.
  Future<Result<void>> disconnectCalendarLocally({
    required String userId,
    required ManagedCalendarEntity calendar,
  }) async {
    try {
      await _remoteDataSource.disconnectCalendarLocally(
        userId: userId,
        calendar: calendar,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Stream<Result<List<CalendarEventEntity>>> watchEvents({
    required String userId,
    String? familyId,
  }) {
    return _remoteDataSource
        .watchEvents(userId: userId, familyId: familyId)
        .map<Result<List<CalendarEventEntity>>>((items) => Success(items))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<CalendarEventEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Stream<Result<List<BusySlotEntity>>> watchFamilyBusySlots(String familyId) {
    return _remoteDataSource
        .watchFamilyBusySlots(familyId)
        .map<Result<List<BusySlotEntity>>>((items) => Success(items))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<BusySlotEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Future<Result<CalendarEventEntity>> createEvent({
    required String userId,
    required String userName,
    String calendarId = 'primary',
    String? familyId,
    required CalendarEventVisibility visibility,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool isAllDay = false,
    String? colorHex,
    int reminderMinutesBefore = 30,
    CalendarRecurrenceRule recurrence = CalendarRecurrenceRule.none,
    required bool publishBusySlot,
    bool syncToGoogle = false,
  }) async {
    try {
      final ev = await _remoteDataSource.createEvent(
        userId: userId,
        userName: userName,
        calendarId: calendarId,
        familyId: familyId,
        visibility: visibility,
        title: title,
        description: description,
        location: location,
        startsAt: startsAt,
        endsAt: endsAt,
        isAllDay: isAllDay,
        colorHex: colorHex,
        reminderMinutesBefore: reminderMinutesBefore,
        recurrence: recurrence,
        publishBusySlot: publishBusySlot,
        syncToGoogle: syncToGoogle,
      );
      return Success(ev);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<CalendarEventEntity>> updateEvent({
    required String userId,
    required String userName,
    required CalendarEventEntity existingEvent,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool? isAllDay,
    String? calendarId,
    String? colorHex,
    int? reminderMinutesBefore,
    CalendarRecurrenceRule? recurrence,
    bool publishBusySlot = false,
    bool syncToGoogle = false,
  }) async {
    try {
      final updated = await _remoteDataSource.updateEvent(
        userId: userId,
        userName: userName,
        existingEvent: existingEvent,
        title: title,
        description: description,
        location: location,
        startsAt: startsAt,
        endsAt: endsAt,
        isAllDay: isAllDay,
        calendarId: calendarId,
        colorHex: colorHex,
        reminderMinutesBefore: reminderMinutesBefore,
        recurrence: recurrence,
        publishBusySlot: publishBusySlot,
        syncToGoogle: syncToGoogle,
      );
      return Success(updated);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> deleteEvent({
    required String userId,
    String? familyId,
    required CalendarEventVisibility visibility,
    required String eventId,
    String? googleCalendarId,
    String? googleEventId,
  }) async {
    try {
      await _remoteDataSource.deleteEvent(
        userId: userId,
        familyId: familyId,
        visibility: visibility,
        eventId: eventId,
        googleCalendarId: googleCalendarId,
        googleEventId: googleEventId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<GoogleCalendarSyncReport>> syncWithGoogleCalendar({
    required String userId,
    required String userName,
    bool interactivePromptIfNeeded = true,
    String? manualAccessTokenOverride,
  }) async {
    try {
      final report = await _remoteDataSource.syncWithGoogleCalendar(
        userId: userId,
        userName: userName,
        interactivePromptIfNeeded: interactivePromptIfNeeded,
        manualAccessTokenOverride: manualAccessTokenOverride,
      );
      return Success(report);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
