import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../domain/entities/calendar_entities.dart';
import '../../domain/repositories/calendar_repository.dart';

class CalendarRemoteDataSource {
  final FirebaseFirestore _firestore;
  static const Uuid _uuid = Uuid();

  const CalendarRemoteDataSource(this._firestore);

  CalendarEventEntity _mapEvent(
    DocumentSnapshot<Map<String, dynamic>> doc,
    CalendarEventVisibility visibility,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final sTs = d['startsAt'];
    final eTs = d['endsAt'];
    return CalendarEventEntity(
      id: (d['id'] as String?) ?? doc.id,
      ownerId: (d['ownerId'] as String?) ?? '',
      ownerName: (d['ownerName'] as String?) ?? 'Cá nhân',
      familyId: d['familyId'] as String?,
      visibility: visibility,
      title: (d['title'] as String?) ?? '',
      description: d['description'] as String?,
      location: d['location'] as String?,
      startsAt: sTs is Timestamp ? sTs.toDate() : DateTime.now(),
      endsAt: eTs is Timestamp ? eTs.toDate() : DateTime.now(),
    );
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

  Future<CalendarEventEntity> createEvent({
    required String userId,
    required String userName,
    String? familyId,
    required CalendarEventVisibility visibility,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    required bool publishBusySlot,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final batch = _firestore.batch();

    final docRef = visibility == CalendarEventVisibility.privateEvent
        ? _firestore.collection('users').doc(userId).collection('private_events').doc(id)
        : _firestore.collection('families').doc(familyId).collection('shared_events').doc(id);

    batch.set(docRef, {
      'id': id,
      'ownerId': userId,
      'ownerName': userName,
      'familyId': visibility == CalendarEventVisibility.sharedEvent ? familyId : null,
      'visibility': visibility.name,
      'title': title,
      'description': description,
      'location': location,
      'startsAt': Timestamp.fromDate(startsAt),
      'endsAt': Timestamp.fromDate(endsAt),
      'createdAt': Timestamp.fromDate(now),
    });

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

  Future<void> deleteEvent({
    required String userId,
    String? familyId,
    required CalendarEventVisibility visibility,
    required String eventId,
  }) async {
    final batch = _firestore.batch();
    if (visibility == CalendarEventVisibility.privateEvent) {
      batch.delete(
        _firestore.collection('users').doc(userId).collection('private_events').doc(eventId),
      );
      if (familyId != null && familyId.isNotEmpty) {
        batch.delete(
          _firestore.collection('families').doc(familyId).collection('availability').doc(eventId),
        );
      }
    } else if (familyId != null && familyId.isNotEmpty) {
      batch.delete(
        _firestore.collection('families').doc(familyId).collection('shared_events').doc(eventId),
      );
    }
    await batch.commit();
  }
}

class CalendarRepositoryImpl implements CalendarRepository {
  final CalendarRemoteDataSource _remoteDataSource;
  const CalendarRepositoryImpl(this._remoteDataSource);

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
            handleError: (Object e, StackTrace _, EventSink<Result<List<BusySlotEntity>>> sink) {
              sink.add(Err(ErrorMapper.map(e)));
            },
          ),
        );
  }

  @override
  Future<Result<CalendarEventEntity>> createEvent({
    required String userId,
    required String userName,
    String? familyId,
    required CalendarEventVisibility visibility,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    required bool publishBusySlot,
  }) async {
    try {
      final ev = await _remoteDataSource.createEvent(
        userId: userId,
        userName: userName,
        familyId: familyId,
        visibility: visibility,
        title: title,
        description: description,
        location: location,
        startsAt: startsAt,
        endsAt: endsAt,
        publishBusySlot: publishBusySlot,
      );
      return Success(ev);
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
  }) async {
    try {
      await _remoteDataSource.deleteEvent(
        userId: userId,
        familyId: familyId,
        visibility: visibility,
        eventId: eventId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
