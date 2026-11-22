import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../domain/entities/calendar_entities.dart';
import '../../domain/repositories/calendar_repository.dart';
import '../datasources/google_calendar_api_datasource.dart';

class CalendarRemoteDataSource {
  final FirebaseFirestore _firestore;
  final GoogleCalendarApiDataSource? _googleApi;
  static const Uuid _uuid = Uuid();

  const CalendarRemoteDataSource(
    this._firestore, {
    GoogleCalendarApiDataSource? googleApi,
  }) : _googleApi = googleApi;

  bool get isGoogleAuthorized => _googleApi?.hasAuthorizedToken ?? false;

  ManagedCalendarEntity _mapCalendarDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String ownerId,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final syncedTs = d['lastSyncedAt'];
    final sourceStr = (d['source'] as String?) ?? CalendarProviderSource.lifeOsPrivate.name;
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
      source: source,
      googleCalendarId: d['googleCalendarId'] as String?,
      googleSyncToken: d['googleSyncToken'] as String?,
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
      'source': cal.source.name,
      'googleCalendarId': cal.googleCalendarId,
      'googleSyncToken': cal.googleSyncToken,
      if (cal.lastSyncedAt != null) 'lastSyncedAt': Timestamp.fromDate(cal.lastSyncedAt!),
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
      final list = snap.docs.map((d) => _mapCalendarDoc(d, userId)).toList();
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

  Future<void> deleteCalendar({
    required String userId,
    required ManagedCalendarEntity calendar,
  }) async {
    if (calendar.isPrimary || calendar.id == 'primary') {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Không thể xóa bộ lịch chính mặc định.',
      );
    }
    if (calendar.googleCalendarId != null &&
        calendar.googleCalendarId!.isNotEmpty &&
        _googleApi != null &&
        _googleApi.hasAuthorizedToken) {
      try {
        final token = await _googleApi.acquireAccessToken(interactive: false);
        await _googleApi.deleteSecondaryCalendar(
          accessToken: token,
          googleCalendarId: calendar.googleCalendarId!,
        );
      } catch (_) {}
    }

    final batch = _firestore.batch();
    final userRef = _firestore.collection('users').doc(userId);
    batch.delete(userRef.collection('calendars').doc(calendar.id));

    final linkedEvents = await userRef
        .collection('private_events')
        .where('calendarId', isEqualTo: calendar.id)
        .get();
    for (final evDoc in linkedEvents.docs) {
      batch.delete(evDoc.reference);
    }
    await batch.commit();
  }

  CalendarEventEntity _mapEvent(
    DocumentSnapshot<Map<String, dynamic>> doc,
    CalendarEventVisibility visibility,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final sTs = d['startsAt'];
    final eTs = d['endsAt'];
    final uTs = d['updatedAt'];
    final syncStr = (d['syncStatus'] as String?) ?? CalendarSyncStatus.localOnly.name;
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
      reminderMinutesBefore: (d['reminderMinutesBefore'] as num?)?.toInt() ?? 30,
      recurrence: CalendarRecurrenceRule.fromRruleString(d['rrule'] as String?),
      googleEventId: d['googleEventId'] as String?,
      googleCalendarId: d['googleCalendarId'] as String?,
      googleEtag: d['googleEtag'] as String?,
      syncStatus: syncStatus,
      updatedAt: uTs is Timestamp ? uTs.toDate() : null,
    );
  }

  Map<String, dynamic> _eventToFirestore(CalendarEventEntity ev, {DateTime? createdAt}) {
    final now = DateTime.now();
    return <String, dynamic>{
      'id': ev.id,
      'calendarId': ev.calendarId,
      'ownerId': ev.ownerId,
      'ownerName': ev.ownerName,
      'familyId': ev.visibility == CalendarEventVisibility.sharedEvent ? ev.familyId : null,
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

  Future<String> _resolveTargetGoogleCalendarId(String userId, String calendarId) async {
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
      familyId: visibility == CalendarEventVisibility.sharedEvent ? familyId : null,
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
      syncStatus: syncToGoogle ? CalendarSyncStatus.pendingUpload : CalendarSyncStatus.localOnly,
      updatedAt: now,
    );

    if (syncToGoogle && visibility == CalendarEventVisibility.privateEvent && _googleApi != null) {
      try {
        final token = await _googleApi.acquireAccessToken(interactive: false);
        final targetGCalId = await _resolveTargetGoogleCalendarId(userId, calendarId);
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
      } catch (_) {
        // Queued as pendingUpload; next syncWithGoogleCalendar pushes automatically!
        draft = draft.copyWith(syncStatus: CalendarSyncStatus.pendingUpload);
      }
    }

    final batch = _firestore.batch();
    final docRef = visibility == CalendarEventVisibility.privateEvent
        ? _firestore.collection('users').doc(userId).collection('private_events').doc(id)
        : _firestore.collection('families').doc(familyId).collection('shared_events').doc(id);

    batch.set(docRef, _eventToFirestore(draft, createdAt: now));

    // Opt-in availability only publishes redacted busy window (NEVER title or description!)
    if (visibility == CalendarEventVisibility.privateEvent &&
        publishBusySlot &&
        familyId != null &&
        familyId.isNotEmpty) {
      final slotRef =
          _firestore.collection('families').doc(familyId).collection('availability').doc(id);
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
    final shouldSyncGoogle = syncToGoogle || existingEvent.isLinkedWithGoogle;

    var updated = existingEvent.copyWith(
      calendarId: calendarId ?? existingEvent.calendarId,
      title: title,
      description: description,
      location: location,
      startsAt: startsAt,
      endsAt: endsAt,
      isAllDay: isAllDay ?? existingEvent.isAllDay,
      colorHex: colorHex ?? existingEvent.colorHex,
      reminderMinutesBefore: reminderMinutesBefore ?? existingEvent.reminderMinutesBefore,
      recurrence: recurrence ?? existingEvent.recurrence,
      syncStatus:
          shouldSyncGoogle ? CalendarSyncStatus.pendingUpload : existingEvent.syncStatus,
      updatedAt: now,
    );

    if (shouldSyncGoogle &&
        updated.visibility == CalendarEventVisibility.privateEvent &&
        _googleApi != null) {
      try {
        final token = await _googleApi.acquireAccessToken(interactive: false);
        final targetGCalId = updated.googleCalendarId ??
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
        updated = updated.copyWith(syncStatus: CalendarSyncStatus.pendingUpload);
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
    if (visibility == CalendarEventVisibility.privateEvent) {
      final docRef =
          _firestore.collection('users').doc(userId).collection('private_events').doc(eventId);
      final snap = await docRef.get();
      final gEvId = googleEventId ?? (snap.data()?['googleEventId'] as String?);
      final gCalId = googleCalendarId ?? (snap.data()?['googleCalendarId'] as String?) ?? 'primary';

      if (gEvId != null && gEvId.isNotEmpty && _googleApi != null) {
        try {
          final token = await _googleApi.acquireAccessToken(interactive: false);
          await _googleApi.deleteEvent(
            accessToken: token,
            googleCalendarId: gCalId,
            googleEventId: gEvId,
          );
        } catch (_) {
          // Offline safety: mark tombstone so next sync deletes remotely on Google Calendar!
          await docRef.set(
            {
              'syncStatus': CalendarSyncStatus.pendingDelete.name,
              'updatedAt': Timestamp.fromDate(DateTime.now()),
            },
            SetOptions(merge: true),
          );
          return;
        }
      }

      final batch = _firestore.batch();
      batch.delete(docRef);
      if (familyId != null && familyId.isNotEmpty) {
        batch.delete(
          _firestore.collection('families').doc(familyId).collection('availability').doc(eventId),
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

  /// Two-way incremental synchronization with Google Calendar REST API v3:
  /// 1. Synchronizes user's `CalendarList`
  /// 2. Pushes local `pendingDelete` & `pendingUpload` / unsynced private events to Google Calendar
  /// 3. Pulls remote changes (`confirmed`, `tentative`, `cancelled`, `RRULE`) via `syncToken` delta!
  Future<GoogleCalendarSyncReport> syncWithGoogleCalendar({
    required String userId,
    required String userName,
    bool interactivePromptIfNeeded = true,
    String? manualAccessTokenOverride,
  }) async {
    final api = _googleApi;
    if (api == null) {
      throw const AppException(
        code: 'GCAL_UNAVAILABLE',
        message: 'Chưa cấu hình GoogleCalendarApiDataSource.',
      );
    }

    final accessToken = await api.acquireAccessToken(
      interactive: interactivePromptIfNeeded,
      manualTokenOverride: manualAccessTokenOverride,
    );

    final userRef = _firestore.collection('users').doc(userId);
    final calendarsCol = userRef.collection('calendars');
    final eventsCol = userRef.collection('private_events');

    // 1. Sync CalendarList metadata while preserving existing local syncTokens & selection flags
    final existingCalDocs = await calendarsCol.get();
    final existingCalById = <String, ManagedCalendarEntity>{
      for (final doc in existingCalDocs.docs) doc.id: _mapCalendarDoc(doc, userId),
    };

    final remoteCalendars = await api.listCalendars(
      accessToken: accessToken,
      ownerId: userId,
    );

    final calBatch = _firestore.batch();
    final syncedCalendars = <ManagedCalendarEntity>[];
    for (final rc in remoteCalendars) {
      final prev = existingCalById[rc.id];
      final merged = rc.copyWith(
        isSelected: prev?.isSelected ?? rc.isSelected,
        googleSyncToken: prev?.googleSyncToken,
        lastSyncedAt: prev?.lastSyncedAt,
      );
      syncedCalendars.add(merged);
      calBatch.set(calendarsCol.doc(merged.id), _calendarToFirestore(merged), SetOptions(merge: true));
    }
    await calBatch.commit();

    var pushedUpserted = 0;
    var pushedDeleted = 0;
    var pulledUpserted = 0;
    var pulledDeleted = 0;
    var usedIncremental = false;

    // 2. Push local pending deletes & pending uploads / localOnly private events
    final localDocsSnap = await eventsCol.get();
    final localByGoogleEventId = <String, CalendarEventEntity>{};

    for (final doc in localDocsSnap.docs) {
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
        await doc.reference.delete();
        continue;
      }

      if (ev.syncStatus == CalendarSyncStatus.pendingUpload ||
          ev.syncStatus == CalendarSyncStatus.localOnly) {
        final targetGCalId =
            ev.googleCalendarId ?? await _resolveTargetGoogleCalendarId(userId, ev.calendarId);
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
        await doc.reference.set(_eventToFirestore(syncedEv), SetOptions(merge: true));
        localByGoogleEventId[remoteRes.googleEventId] = syncedEv;
        pushedUpserted++;
      } else if (ev.isLinkedWithGoogle) {
        localByGoogleEventId[ev.googleEventId!] = ev;
      }
    }

    // 3. Pull delta changes for each selected Google Calendar (Primary + selected secondary calendars)
    final activeGoogleCals = syncedCalendars.where((c) => c.isSelected && c.isGoogleSynced).toList();
    final now = DateTime.now();

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
        final matchedLocal = localByGoogleEventId[remoteEv.googleEventId];
        if (remoteEv.isCancelled) {
          if (matchedLocal != null) {
            pullBatch.delete(eventsCol.doc(matchedLocal.id));
            pulledDeleted++;
          }
          continue;
        }

        // Skip overwriting if we JUST pushed this exact version in Step 2
        if (matchedLocal != null &&
            matchedLocal.googleEtag != null &&
            matchedLocal.googleEtag == remoteEv.etag) {
          continue;
        }

        final docId = matchedLocal?.id ?? 'gcal_${remoteEv.googleEventId}';
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
      pullBatch.set(calendarsCol.doc(gCal.id), _calendarToFirestore(updatedCal), SetOptions(merge: true));
      await pullBatch.commit();
    }

    return GoogleCalendarSyncReport(
      calendarsSynced: activeGoogleCals.length,
      pulledUpserted: pulledUpserted,
      pulledDeleted: pulledDeleted,
      pushedUpserted: pushedUpserted,
      pushedDeleted: pushedDeleted,
      usedIncrementalSyncToken: usedIncremental,
      syncedAt: now,
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
                (Object e, StackTrace _, EventSink<Result<List<ManagedCalendarEntity>>> sink) {
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
      await _remoteDataSource.deleteCalendar(userId: userId, calendar: calendar);
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
                (Object e, StackTrace _, EventSink<Result<List<CalendarEventEntity>>> sink) {
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
                (Object e, StackTrace _, EventSink<Result<List<BusySlotEntity>>> sink) {
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
