import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/pro_utilities_entities.dart';
import '../../domain/repositories/pro_utilities_repository.dart';

class ProUtilitiesRepositoryImpl implements ProUtilitiesRepository {
  final FirebaseFirestore _firestore;
  static const Uuid _uuid = Uuid();

  const ProUtilitiesRepositoryImpl(this._firestore);

  DocumentReference<Map<String, dynamic>> _userRef(String userId) =>
      _firestore.collection('users').doc(userId);

  @override
  Stream<ProUtilitiesSnapshot> watchAll({required String userId}) {
    final todayKey = LifeHabitEntity.formatDayKey(DateTime.now());
    return Stream<ProUtilitiesSnapshot>.multi((controller) {
      var subs = <SubscriptionWarrantyEntity>[];
      var habits = <LifeHabitEntity>[];
      var wellness = DailyWellnessEntity(dateKey: todayKey);
      var gifts = <GiftLedgerEntryEntity>[];
      var packing = <PackingChecklistItemEntity>[];

      void emitNow() {
        if (controller.isClosed) return;
        controller.add(
          ProUtilitiesSnapshot(
            subscriptionsAndWarranties: subs,
            habits: habits,
            todayWellness: wellness,
            giftEntries: gifts,
            packingItems: packing,
          ),
        );
      }

      final s1 = _userRef(userId)
          .collection('subscriptions_warranties')
          .snapshots()
          .listen((snap) {
            subs =
                snap.docs.map((doc) {
                  final d = doc.data();
                  return SubscriptionWarrantyEntity(
                    id: doc.id,
                    ownerId: userId,
                    title: (d['title'] ?? 'Gói dịch vụ') as String,
                    providerOrStore: (d['providerOrStore'] ?? '') as String,
                    cycle: SubscriptionCycleX.fromKey(d['cycle'] as String?),
                    amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
                    nextBillingOrExpiryDate:
                        DateTime.tryParse(
                          (d['nextBillingOrExpiryDate'] ?? '') as String,
                        ) ??
                        DateTime.now().add(const Duration(days: 30)),
                    serialOrNote: (d['serialOrNote'] ?? '') as String,
                  );
                }).toList()..sort(
                  (a, b) => a.nextBillingOrExpiryDate.compareTo(
                    b.nextBillingOrExpiryDate,
                  ),
                );
            emitNow();
          }, onError: (_) => emitNow());

      final s2 = _userRef(userId).collection('habits').snapshots().listen((
        snap,
      ) {
        habits = snap.docs.map((doc) {
          final d = doc.data();
          final rawList =
              (d['completedDateKeys'] as List<dynamic>?) ?? const [];
          return LifeHabitEntity(
            id: doc.id,
            ownerId: userId,
            title: (d['title'] ?? 'Thói quen tốt') as String,
            categoryTag: (d['categoryTag'] ?? 'Sức khỏe') as String,
            completedDateKeys: rawList.map((e) => e.toString()).toList(),
          );
        }).toList();
        emitNow();
      }, onError: (_) => emitNow());

      final s3 = _userRef(userId)
          .collection('wellness_daily')
          .doc(todayKey)
          .snapshots()
          .listen((doc) {
            final d = doc.data() ?? const <String, dynamic>{};
            wellness = DailyWellnessEntity(
              dateKey: todayKey,
              waterMl: (d['waterMl'] as num?)?.toInt() ?? 0,
              targetWaterMl: (d['targetWaterMl'] as num?)?.toInt() ?? 2000,
              focusMinutes: (d['focusMinutes'] as num?)?.toInt() ?? 0,
              completedPomodoros:
                  (d['completedPomodoros'] as num?)?.toInt() ?? 0,
            );
            emitNow();
          }, onError: (_) => emitNow());

      final s4 = _userRef(userId).collection('gift_ledger').snapshots().listen((
        snap,
      ) {
        gifts = snap.docs.map((doc) {
          final d = doc.data();
          return GiftLedgerEntryEntity(
            id: doc.id,
            ownerId: userId,
            contactName: (d['contactName'] ?? '') as String,
            relationshipGroup: (d['relationshipGroup'] ?? 'Bạn bè') as String,
            direction: d['direction'] == 'received'
                ? GiftDirection.received
                : GiftDirection.gave,
            occasion: GiftOccasionX.fromKey(d['occasion'] as String?),
            amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
            note: (d['note'] ?? '') as String,
            eventDate:
                DateTime.tryParse((d['eventDate'] ?? '') as String) ??
                DateTime.now(),
          );
        }).toList()..sort((a, b) => b.eventDate.compareTo(a.eventDate));
        emitNow();
      }, onError: (_) => emitNow());

      final s5 = _userRef(userId)
          .collection('packing_items')
          .snapshots()
          .listen((snap) {
            packing = snap.docs.map((doc) {
              final d = doc.data();
              return PackingChecklistItemEntity(
                id: doc.id,
                ownerId: userId,
                tripName: (d['tripName'] ?? 'Chuyến đi') as String,
                title: (d['title'] ?? '') as String,
                checked: d['checked'] == true,
              );
            }).toList();
            emitNow();
          }, onError: (_) => emitNow());

      controller.onCancel = () async {
        await s1.cancel();
        await s2.cancel();
        await s3.cancel();
        await s4.cancel();
        await s5.cancel();
      };
    });
  }

  @override
  Future<Result<void>> addSubscriptionOrWarranty({
    required String userId,
    required String title,
    required String providerOrStore,
    required SubscriptionCycle cycle,
    required int amountMinor,
    required DateTime nextBillingOrExpiryDate,
    String serialOrNote = '',
  }) => saveSubscriptionOrWarranty(
    userId: userId,
    title: title,
    providerOrStore: providerOrStore,
    cycle: cycle,
    amountMinor: amountMinor,
    nextBillingOrExpiryDate: nextBillingOrExpiryDate,
    serialOrNote: serialOrNote,
  );

  @override
  Future<Result<void>> saveSubscriptionOrWarranty({
    required String userId,
    String? itemId,
    required String title,
    required String providerOrStore,
    required SubscriptionCycle cycle,
    required int amountMinor,
    required DateTime nextBillingOrExpiryDate,
    String serialOrNote = '',
  }) async {
    if (title.trim().isEmpty) {
      return const Err(
        ValidationFailure(
          message: 'Vui lòng nhập tên gói dịch vụ hoặc thiết bị bảo hành.',
        ),
      );
    }
    try {
      final isUpdate = itemId != null && itemId.trim().isNotEmpty;
      final id = isUpdate ? itemId.trim() : 'sub_${_uuid.v4().substring(0, 8)}';
      await _userRef(
        userId,
      ).collection('subscriptions_warranties').doc(id).set({
        'id': id,
        'ownerId': userId,
        'title': title.trim(),
        'providerOrStore': providerOrStore.trim(),
        'cycle': cycle.key,
        'amountMinor': amountMinor < 0 ? 0 : amountMinor,
        'nextBillingOrExpiryDate': nextBillingOrExpiryDate.toIso8601String(),
        'serialOrNote': serialOrNote.trim(),
      }, SetOptions(merge: true));
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể lưu dữ liệu: $e'));
    }
  }

  @override
  Future<Result<void>> deleteSubscriptionOrWarranty({
    required String userId,
    required String itemId,
  }) async {
    try {
      await _userRef(
        userId,
      ).collection('subscriptions_warranties').doc(itemId).delete();
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể xóa mục: $e'));
    }
  }

  @override
  Future<Result<void>> addHabit({
    required String userId,
    required String title,
    required String categoryTag,
  }) async {
    if (title.trim().isEmpty) {
      return const Err(
        ValidationFailure(message: 'Vui lòng nhập tên thói quen.'),
      );
    }
    try {
      final id = 'hab_${_uuid.v4().substring(0, 8)}';
      await _userRef(userId).collection('habits').doc(id).set({
        'id': id,
        'ownerId': userId,
        'title': title.trim(),
        'categoryTag': categoryTag,
        'completedDateKeys': <String>[],
      });
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể tạo thói quen: $e'));
    }
  }

  @override
  Future<Result<void>> updateHabit({
    required String userId,
    required String habitId,
    required String title,
    required String categoryTag,
  }) async {
    if (title.trim().isEmpty) {
      return const Err(
        ValidationFailure(message: 'Vui lòng nhập tên thói quen.'),
      );
    }
    try {
      await _userRef(userId).collection('habits').doc(habitId).update({
        'title': title.trim(),
        'categoryTag': categoryTag,
      });
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể cập nhật thói quen: $e'),
      );
    }
  }

  @override
  Future<Result<void>> deleteHabit({
    required String userId,
    required String habitId,
  }) async {
    try {
      await _userRef(userId).collection('habits').doc(habitId).delete();
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể xóa thói quen: $e'));
    }
  }

  @override
  Future<Result<void>> toggleHabitToday({
    required String userId,
    required LifeHabitEntity habit,
    required DateTime date,
  }) async {
    try {
      final key = LifeHabitEntity.formatDayKey(date);
      final updated = habit.completedDateKeys.toSet();
      if (updated.contains(key)) {
        updated.remove(key);
      } else {
        updated.add(key);
      }
      await _userRef(userId).collection('habits').doc(habit.id).update({
        'completedDateKeys': updated.toList(),
      });
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể cập nhật thói quen: $e'),
      );
    }
  }

  @override
  Future<Result<void>> updateDailyWellness({
    required String userId,
    required String dateKey,
    int addWaterMl = 0,
    int addFocusMinutes = 0,
    int addPomodoros = 0,
  }) async {
    try {
      final docRef = _userRef(userId).collection('wellness_daily').doc(dateKey);
      final snap = await docRef.get();
      final curr = snap.data() ?? const <String, dynamic>{};
      int? profileTarget;
      Map<String, dynamic>? remData;
      if (curr['targetWaterMl'] == null || addWaterMl != 0) {
        final remSnap = await _userRef(
          userId,
        ).collection('medical_profiles').doc('hydration_reminder').get();
        remData = remSnap.data();
        profileTarget = (remData?['targetWaterMl'] as num?)?.toInt();
      }
      final preservedTarget =
          (curr['targetWaterMl'] as num?)?.toInt() ?? profileTarget ?? 2000;
      final nextWater = (((curr['waterMl'] as num?)?.toInt() ?? 0) + addWaterMl)
          .clamp(0, 10000);
      final nextFocus =
          (((curr['focusMinutes'] as num?)?.toInt() ?? 0) + addFocusMinutes)
              .clamp(0, 1440);
      final nextPomo =
          (((curr['completedPomodoros'] as num?)?.toInt() ?? 0) + addPomodoros)
              .clamp(0, 50);

      final rawEntries = curr['entries'];
      final entries = <Map<String, dynamic>>[
        if (rawEntries is List)
          for (final item in rawEntries)
            if (item is Map) Map<String, dynamic>.from(item),
      ];
      if (addWaterMl > 0) {
        final now = DateTime.now();
        entries.add(<String, dynamic>{
          'id': 'cup_${now.microsecondsSinceEpoch}',
          'ml': addWaterMl,
          'beverageLabel': 'Nước lọc',
          'loggedAt': now.toIso8601String(),
        });
      }

      await docRef.set({
        'dateKey': dateKey,
        'ownerId': userId,
        'waterMl': nextWater,
        'targetWaterMl': preservedTarget,
        if (addWaterMl > 0) 'lastCupMl': addWaterMl,
        if (addWaterMl > 0) 'entries': entries,
        'focusMinutes': nextFocus,
        'completedPomodoros': nextPomo,
      }, SetOptions(merge: true));

      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể lưu chỉ số sức khỏe: $e'),
      );
    }
  }

  @override
  Future<Result<void>> addGiftEntry({
    required String userId,
    required String contactName,
    required String relationshipGroup,
    required GiftDirection direction,
    required GiftOccasion occasion,
    required int amountMinor,
    DateTime? eventDate,
    String note = '',
  }) async {
    if (contactName.trim().isEmpty || amountMinor <= 0) {
      return const Err(
        ValidationFailure(
          message: 'Vui lòng nhập tên người mừng và số tiền hợp lệ.',
        ),
      );
    }
    try {
      final id = 'gift_${_uuid.v4().substring(0, 8)}';
      await _userRef(userId).collection('gift_ledger').doc(id).set({
        'id': id,
        'ownerId': userId,
        'contactName': contactName.trim(),
        'relationshipGroup': relationshipGroup,
        'direction': direction.name,
        'occasion': occasion.name,
        'amountMinor': amountMinor,
        'note': note.trim(),
        'eventDate': (eventDate ?? DateTime.now()).toIso8601String(),
      });
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể lưu sổ hiếu hỷ: $e'));
    }
  }

  @override
  Future<Result<void>> updateGiftEntry({
    required String userId,
    required String entryId,
    required String contactName,
    required String relationshipGroup,
    required GiftDirection direction,
    required GiftOccasion occasion,
    required int amountMinor,
    required DateTime eventDate,
    String note = '',
  }) async {
    if (contactName.trim().isEmpty || amountMinor <= 0) {
      return const Err(
        ValidationFailure(
          message: 'Vui lòng nhập tên người mừng và số tiền hợp lệ.',
        ),
      );
    }
    try {
      await _userRef(userId).collection('gift_ledger').doc(entryId).update({
        'contactName': contactName.trim(),
        'relationshipGroup': relationshipGroup,
        'direction': direction.name,
        'occasion': occasion.name,
        'amountMinor': amountMinor,
        'note': note.trim(),
        'eventDate': eventDate.toIso8601String(),
      });
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể cập nhật mục Hiếu Hỷ: $e'),
      );
    }
  }

  @override
  Future<Result<void>> deleteGiftEntry({
    required String userId,
    required String entryId,
  }) async {
    try {
      await _userRef(userId).collection('gift_ledger').doc(entryId).delete();
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể xóa mục Hiếu Hỷ: $e'));
    }
  }

  @override
  Future<Result<void>> seedPackingTemplate({
    required String userId,
    required String tripName,
    required List<String> itemTitles,
  }) async {
    try {
      final col = _userRef(userId).collection('packing_items');
      final existing = await col.get();
      final batch = _firestore.batch();
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }
      for (final item in itemTitles) {
        final id = 'pack_${_uuid.v4().substring(0, 8)}';
        batch.set(col.doc(id), {
          'id': id,
          'ownerId': userId,
          'tripName': tripName,
          'title': item,
          'checked': false,
        });
      }
      await batch.commit();
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể tạo checklist hành lý: $e'),
      );
    }
  }

  @override
  Future<Result<void>> addPackingItem({
    required String userId,
    required String tripName,
    required String title,
  }) async {
    if (title.trim().isEmpty) {
      return const Err(
        ValidationFailure(message: 'Vui lòng nhập tên vật dụng cần mang.'),
      );
    }
    try {
      final id = 'pack_${_uuid.v4().substring(0, 8)}';
      await _userRef(userId).collection('packing_items').doc(id).set({
        'id': id,
        'ownerId': userId,
        'tripName': tripName.trim().isEmpty ? 'Chuyến đi' : tripName.trim(),
        'title': title.trim(),
        'checked': false,
      });
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể thêm vật dụng hành lý: $e'),
      );
    }
  }

  @override
  Future<Result<void>> deletePackingItem({
    required String userId,
    required String itemId,
  }) async {
    try {
      await _userRef(userId).collection('packing_items').doc(itemId).delete();
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể xóa vật dụng hành lý: $e'),
      );
    }
  }

  @override
  Future<Result<void>> togglePackingItem({
    required String userId,
    required PackingChecklistItemEntity item,
  }) async {
    try {
      await _userRef(userId).collection('packing_items').doc(item.id).update({
        'checked': !item.checked,
      });
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể cập nhật hành lý: $e'));
    }
  }
}
