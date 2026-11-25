import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/services/health_reminder_scheduler_service.dart';
import '../../../../core/services/native_alarm_scheduler_bridge.dart';
import '../../domain/entities/daily_life_entities.dart';
import '../../domain/repositories/daily_life_repository.dart';

class DailyLifeRepositoryImpl implements DailyLifeRepository {
  final FirebaseFirestore _firestore;
  final HealthReminderSchedulerService _reminderScheduler;
  static const Uuid _uuid = Uuid();

  DailyLifeRepositoryImpl(
    this._firestore, {
    HealthReminderSchedulerService? reminderScheduler,
  }) : _reminderScheduler =
           reminderScheduler ?? HealthReminderSchedulerService();

  DocumentReference<Map<String, dynamic>> _userRef(String userId) =>
      _firestore.collection('users').doc(userId);

  @override
  Stream<DailyLifeSnapshot> watchAll({required String userId}) {
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return Stream<DailyLifeSnapshot>.multi((controller) {
      var meds = <MedicationCabinetItemEntity>[];
      var healthLogs = <HealthVitalLogEntity>[];
      var emergencyCard = EmergencyMedicalCardEntity(ownerId: userId);
      var waterMl = 0;
      int? dailyTargetWaterMl;
      int? profileTargetWaterMl;
      var lastCupMl = 250;
      var waterReminderEnabled = false;
      var waterIntervalMinutes = 90;
      var waterStartHour = 7;
      var waterStartMinute = 0;
      var waterEndHour = 21;
      var waterEndMinute = 0;
      double? profileWeightKg;
      double? profileHeightCm;
      var activityLevel = HydrationActivityLevel.sedentary;
      var autoSyncTargetByBody = true;
      var preferredCupMl = 250;
      DateTime? snoozedUntil;
      var hydrationProfileLoaded = false;
      var todayEntries = <WaterIntakeLogEntry>[];
      var groceries = <SmartGroceryItemEntity>[];
      var mealPlans = <DailyMealPlanEntity>[];
      var readings = <UtilityMeterReadingEntity>[];
      var contracts = <HomeContractMaintenanceEntity>[];
      var notes = <SmartLifeNoteEntity>[];

      void emitNow() {
        if (controller.isClosed) return;
        final resolvedWeight =
            profileWeightKg ??
            (healthLogs.isNotEmpty ? healthLogs.first.weightKg : 63.0);
        final resolvedHeight =
            profileHeightCm ??
            (healthLogs.isNotEmpty ? healthLogs.first.heightCm : 168.0);
        final computedBodyTarget =
            AsianHealthBmiTdeeEngine.computeRecommendedWaterMl(
              weightKg: resolvedWeight,
              heightCm: resolvedHeight,
              activityLevel: activityLevel,
            );
        final resolvedTarget =
            profileTargetWaterMl ??
            dailyTargetWaterMl ??
            ((profileWeightKg != null || healthLogs.isNotEmpty) &&
                    autoSyncTargetByBody
                ? computedBodyTarget
                : 2000);

        if (hydrationProfileLoaded) {
          unawaited(
            NativeAlarmSchedulerBridge.instance.syncHydrationDaemon(
              enabled: waterReminderEnabled,
              intervalMinutes: waterIntervalMinutes,
              startHour: waterStartHour,
              startMinute: waterStartMinute,
              endHour: waterEndHour,
              endMinute: waterEndMinute,
              targetWaterMl: resolvedTarget,
              waterMl: waterMl,
              preferredCupMl: preferredCupMl,
              dayKey: todayKey,
            ),
          );
        }

        controller.add(
          DailyLifeSnapshot(
            medications: meds,
            healthLogs: healthLogs,
            emergencyCard: emergencyCard,
            hydration: HydrationReminderStatusEntity(
              dayKey: todayKey,
              waterMl: waterMl,
              targetWaterMl: resolvedTarget,
              lastCupMl: lastCupMl,
              reminderEnabled: waterReminderEnabled,
              intervalMinutes: waterIntervalMinutes,
              startHour: waterStartHour,
              startMinute: waterStartMinute,
              endHour: waterEndHour,
              endMinute: waterEndMinute,
              weightKg: resolvedWeight,
              heightCm: resolvedHeight,
              activityLevel: activityLevel,
              autoSyncTargetByBody: autoSyncTargetByBody,
              preferredCupMl: preferredCupMl,
              snoozedUntil: snoozedUntil,
              todayEntries: todayEntries,
            ),
            groceryItems: groceries,
            mealPlans: mealPlans,
            utilityReadings: readings,
            homeContracts: contracts,
            notes: notes,
          ),
        );
      }

      final s1 = _userRef(userId)
          .collection('medications')
          .limit(60)
          .snapshots()
          .listen((snap) {
            meds = snap.docs.map((doc) {
              final d = doc.data();
              final slot = MedicationScheduleSlot.fromName(
                d['slot'] as String?,
              );
              return MedicationCabinetItemEntity(
                id: doc.id,
                ownerId: userId,
                name: (d['name'] ?? 'Thuốc / Vitamin') as String,
                dosage: (d['dosage'] ?? '1 viên') as String,
                slot: slot,
                remainingPills: (d['remainingPills'] as num?)?.toInt() ?? 0,
                expiryDate:
                    DateTime.tryParse((d['expiryDate'] ?? '') as String) ??
                    DateTime.now().add(const Duration(days: 180)),
                inventoryConfirmed: d['inventoryConfirmed'] is bool
                    ? d['inventoryConfirmed'] as bool
                    : true,
                lastTakenDayKey: d['lastTakenDayKey'] as String?,
                memberName: (d['memberName'] ?? 'Cả gia đình') as String,
                reminderEnabled: d['reminderEnabled'] is bool
                    ? d['reminderEnabled'] as bool
                    : slot.isScheduledDaily,
                reminderHour: (d['reminderHour'] as num?)?.toInt() ??
                    slot.defaultHour,
                reminderMinute: (d['reminderMinute'] as num?)?.toInt() ??
                    slot.defaultMinute,
              );
            }).toList()..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
            emitNow();
          });

      final s2 = _userRef(userId)
          .collection('health_logs')
          .limit(45)
          .snapshots()
          .listen((snap) {
            healthLogs = snap.docs.map((doc) {
              final d = doc.data();
              return HealthVitalLogEntity(
                id: doc.id,
                ownerId: userId,
                weightKg: (d['weightKg'] as num?)?.toDouble() ?? 62.0,
                heightCm: (d['heightCm'] as num?)?.toDouble() ?? 168.0,
                systolicMmHg: (d['systolicMmHg'] as num?)?.toInt() ?? 118,
                diastolicMmHg: (d['diastolicMmHg'] as num?)?.toInt() ?? 76,
                heartRateBpm: (d['heartRateBpm'] as num?)?.toInt() ?? 72,
                sleepHours: (d['sleepHours'] as num?)?.toDouble() ?? 7.5,
                recordedAt:
                    DateTime.tryParse((d['recordedAt'] ?? '') as String) ??
                    DateTime.now(),
                note: (d['note'] ?? '') as String,
              );
            }).toList()..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
            emitNow();
          });

      final s3 = _userRef(userId)
          .collection('medical_profiles')
          .doc('emergency_card')
          .snapshots()
          .listen((doc) {
            if (doc.exists && doc.data() != null) {
              final d = doc.data()!;
              emergencyCard = EmergencyMedicalCardEntity(
                ownerId: userId,
                bloodType: ((d['bloodType'] ?? '') as String).trim(),
                allergies: ((d['allergies'] ?? '') as String).trim(),
                chronicConditions: ((d['chronicConditions'] ?? '') as String)
                    .trim(),
                insuranceCode: ((d['insuranceCode'] ?? '') as String).trim(),
                emergencyContactName:
                    ((d['emergencyContactName'] ?? '') as String).trim(),
                emergencyContactPhone:
                    ((d['emergencyContactPhone'] ?? '') as String).trim(),
                preferredHospital: ((d['preferredHospital'] ?? '') as String)
                    .trim(),
              );
            } else {
              emergencyCard = EmergencyMedicalCardEntity(ownerId: userId);
            }
            emitNow();
          });

      final s4 = _userRef(userId)
          .collection('grocery_items')
          .limit(100)
          .snapshots()
          .listen((snap) {
            groceries = snap.docs.map((doc) {
              final d = doc.data();
              return SmartGroceryItemEntity(
                id: doc.id,
                ownerId: userId,
                name: (d['name'] ?? 'Thực phẩm') as String,
                quantityLabel: (d['quantityLabel'] ?? '1 phần') as String,
                aisle: GroceryAisle.fromName(d['aisle'] as String?),
                estimatedMinor: (d['estimatedMinor'] as num?)?.toInt() ?? 0,
                isBought: d['isBought'] == true,
                inFridgeStorage: d['inFridgeStorage'] == true,
                expiryDate: d['expiryDate'] != null
                    ? DateTime.tryParse(d['expiryDate'].toString())
                    : null,
              );
            }).toList();
            emitNow();
          });

      final s5 = _userRef(userId)
          .collection('meal_plans')
          .limit(31)
          .snapshots()
          .listen((snap) {
            mealPlans = snap.docs.map((doc) {
              final d = doc.data();
              return DailyMealPlanEntity(
                dayKey: doc.id,
                ownerId: userId,
                breakfast: (d['breakfast'] ?? '') as String,
                lunch: (d['lunch'] ?? '') as String,
                dinner: (d['dinner'] ?? '') as String,
                estimatedDailyCostMinor:
                    (d['estimatedDailyCostMinor'] as num?)?.toInt() ?? 0,
                estimatedKcal: (d['estimatedKcal'] as num?)?.toInt() ?? 0,
              );
            }).toList()..sort((a, b) => b.dayKey.compareTo(a.dayKey));
            emitNow();
          });

      final s6 = _userRef(userId)
          .collection('utility_readings')
          .limit(36)
          .snapshots()
          .listen((snap) {
            readings = snap.docs.map((doc) {
              final d = doc.data();
              return UtilityMeterReadingEntity(
                id: doc.id,
                ownerId: userId,
                monthKey: (d['monthKey'] ?? '') as String,
                prevElectricKwh: (d['prevElectricKwh'] as num?)?.toInt() ?? 0,
                currElectricKwh: (d['currElectricKwh'] as num?)?.toInt() ?? 0,
                prevWaterM3: (d['prevWaterM3'] as num?)?.toInt() ?? 0,
                currWaterM3: (d['currWaterM3'] as num?)?.toInt() ?? 0,
                useEvnTieredTariff: d['useEvnTieredTariff'] != false,
                fixedServicesMinor:
                    (d['fixedServicesMinor'] as num?)?.toInt() ?? 0,
                totalAmountMinor: (d['totalAmountMinor'] as num?)?.toInt() ?? 0,
                isPaid: d['isPaid'] == true,
                recordedAt:
                    DateTime.tryParse((d['recordedAt'] ?? '') as String) ??
                    DateTime.now(),
              );
            }).toList()..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
            emitNow();
          });

      final s7 = _userRef(userId)
          .collection('home_contracts')
          .snapshots()
          .listen((snap) {
            contracts = snap.docs.map((doc) {
              final d = doc.data();
              return HomeContractMaintenanceEntity(
                id: doc.id,
                ownerId: userId,
                homeName: (d['homeName'] ?? 'Tổ ấm của tôi') as String,
                monthlyRentMinor: (d['monthlyRentMinor'] as num?)?.toInt() ?? 0,
                depositMinor: (d['depositMinor'] as num?)?.toInt() ?? 0,
                paymentDayOfMonth:
                    (d['paymentDayOfMonth'] as num?)?.toInt() ?? 5,
                leaseEndDate:
                    DateTime.tryParse((d['leaseEndDate'] ?? '') as String) ??
                    DateTime.now().add(const Duration(days: 365)),
                wifiCredentials: (d['wifiCredentials'] ?? '') as String,
                nextApplianceMaintenanceNote:
                    (d['nextApplianceMaintenanceNote'] ?? '') as String,
              );
            }).toList();
            emitNow();
          });

      final s8 = _userRef(userId)
          .collection('life_notes')
          .limit(80)
          .snapshots()
          .listen((snap) {
            notes =
                snap.docs.map((doc) {
                  final d = doc.data();
                  return SmartLifeNoteEntity(
                    id: doc.id,
                    ownerId: userId,
                    title: (d['title'] ?? 'Ghi chú') as String,
                    content: (d['content'] ?? '') as String,
                    categoryTag:
                        (d['categoryTag'] ?? 'Ghi chú nhanh') as String,
                    mood: d['mood'] != null
                        ? LifeMoodLevel.fromName(d['mood'] as String?)
                        : null,
                    isPinned: d['isPinned'] == true,
                    updatedAt:
                        DateTime.tryParse((d['updatedAt'] ?? '') as String) ??
                        DateTime.now(),
                  );
                }).toList()..sort((a, b) {
                  if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
                  return b.updatedAt.compareTo(a.updatedAt);
                });
            emitNow();
          });

      final s9 = _userRef(userId)
          .collection('wellness_daily')
          .doc(todayKey)
          .snapshots()
          .listen((doc) {
            final d = doc.data();
            if (d != null) {
              waterMl = (d['waterMl'] as num?)?.toInt() ?? 0;
              dailyTargetWaterMl = (d['targetWaterMl'] as num?)?.toInt();
              if (d['lastCupMl'] != null) {
                lastCupMl = (d['lastCupMl'] as num).toInt();
              }
              final rawEntries = d['entries'];
              if (rawEntries is List) {
                todayEntries =
                    rawEntries
                        .map(WaterIntakeLogEntry.fromMap)
                        .whereType<WaterIntakeLogEntry>()
                        .toList()
                      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
              } else {
                todayEntries = <WaterIntakeLogEntry>[];
              }
            } else {
              waterMl = 0;
              dailyTargetWaterMl = null;
              todayEntries = <WaterIntakeLogEntry>[];
            }
            emitNow();
          });

      final s10 = _userRef(userId)
          .collection('medical_profiles')
          .doc('hydration_reminder')
          .snapshots()
          .listen((doc) {
            final d = doc.data();
            hydrationProfileLoaded = d != null;
            if (d != null) {
              waterReminderEnabled = d['reminderEnabled'] == true;
              waterIntervalMinutes =
                  (d['intervalMinutes'] as num?)?.toInt() ?? 90;
              waterStartHour = (d['startHour'] as num?)?.toInt() ?? 7;
              waterStartMinute = (d['startMinute'] as num?)?.toInt() ?? 0;
              waterEndHour = (d['endHour'] as num?)?.toInt() ?? 21;
              waterEndMinute = (d['endMinute'] as num?)?.toInt() ?? 0;
              profileTargetWaterMl = (d['targetWaterMl'] as num?)?.toInt();
              profileWeightKg = (d['weightKg'] as num?)?.toDouble();
              profileHeightCm = (d['heightCm'] as num?)?.toDouble();
              activityLevel = HydrationActivityLevel.fromName(
                d['activityLevel'] as String?,
              );
              autoSyncTargetByBody = d['autoSyncTargetByBody'] != false;
              preferredCupMl = ((d['preferredCupMl'] as num?)?.toInt() ?? 250)
                  .clamp(100, 600);
              snoozedUntil = d['snoozedUntil'] != null
                  ? DateTime.tryParse(d['snoozedUntil'].toString())
                  : null;
            }
            emitNow();
          });

      controller.onCancel = () async {
        await Future.wait([
          s1.cancel(),
          s2.cancel(),
          s3.cancel(),
          s4.cancel(),
          s5.cancel(),
          s6.cancel(),
          s7.cancel(),
          s8.cancel(),
          s9.cancel(),
          s10.cancel(),
        ]);
      };
    });
  }

  @override
  Future<Result<void>> addMedication({
    required String userId,
    required String name,
    required String dosage,
    required MedicationScheduleSlot slot,
    required int remainingPills,
    required DateTime expiryDate,
    bool inventoryConfirmed = true,
    String memberName = 'Cả gia đình',
    bool? reminderEnabled,
    int? reminderHour,
    int? reminderMinute,
  }) async {
    try {
      final id = 'med_${_uuid.v4().substring(0, 8)}';
      final resolvedEnabled = reminderEnabled ?? slot.isScheduledDaily;
      final resolvedHour = reminderHour ?? slot.defaultHour;
      final resolvedMin = reminderMinute ?? slot.defaultMinute;

      await _userRef(userId).collection('medications').doc(id).set({
        'id': id,
        'ownerId': userId,
        'name': name.trim(),
        'dosage': dosage.trim(),
        'slot': slot.name,
        'remainingPills': remainingPills,
        'expiryDate': expiryDate.toIso8601String(),
        'inventoryConfirmed': inventoryConfirmed,
        'lastTakenDayKey': null,
        'memberName': memberName.trim(),
        'reminderEnabled': resolvedEnabled,
        'reminderHour': resolvedHour,
        'reminderMinute': resolvedMin,
      });

      final entity = MedicationCabinetItemEntity(
        id: id,
        ownerId: userId,
        name: name.trim(),
        dosage: dosage.trim(),
        slot: slot,
        remainingPills: remainingPills,
        expiryDate: expiryDate,
        inventoryConfirmed: inventoryConfirmed,
        memberName: memberName.trim(),
        reminderEnabled: resolvedEnabled,
        reminderHour: resolvedHour,
        reminderMinute: resolvedMin,
      );
      await _reminderScheduler.syncMedicationAlarm(entity);
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể lưu thuốc/vitamin: $e'));
    }
  }

  @override
  Future<Result<void>> updateMedicationReminder({
    required String userId,
    required MedicationCabinetItemEntity item,
    required bool reminderEnabled,
    required int reminderHour,
    required int reminderMinute,
  }) async {
    try {
      await _userRef(userId).collection('medications').doc(item.id).update({
        'reminderEnabled': reminderEnabled,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
      });
      final updated = item.copyWith(
        reminderEnabled: reminderEnabled,
        reminderHour: reminderHour,
        reminderMinute: reminderMinute,
      );
      await _reminderScheduler.syncMedicationAlarm(updated);
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể cập nhật giờ nhắc thuốc: $e'),
      );
    }
  }

  @override
  Future<Result<void>> snoozeMedication15Min({
    required MedicationCabinetItemEntity item,
  }) async {
    try {
      await _reminderScheduler.snoozeMedication15Min(item);
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể dời chuông nhắc thuốc: $e'),
      );
    }
  }

  @override
  Future<Result<void>> toggleMedicationToday({
    required String userId,
    required MedicationCabinetItemEntity item,
    required String dayKey,
  }) async {
    try {
      final alreadyTaken = item.isTakenOn(dayKey);
      final nextRemaining = alreadyTaken
          ? item.remainingPills + 1
          : (item.remainingPills > 0 ? item.remainingPills - 1 : 0);
      await _userRef(userId).collection('medications').doc(item.id).update({
        'lastTakenDayKey': alreadyTaken ? null : dayKey,
        'remainingPills': nextRemaining,
      });
      final updated = item.copyWith(
        lastTakenDayKey: dayKey,
        clearLastTaken: alreadyTaken,
        remainingPills: nextRemaining,
      );
      await _reminderScheduler.syncMedicationAlarm(updated, todayKey: dayKey);
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể cập nhật lịch uống thuốc: $e'),
      );
    }
  }

  @override
  Future<Result<void>> deleteMedication({
    required String userId,
    required String medId,
  }) async {
    try {
      await _userRef(userId).collection('medications').doc(medId).delete();
      await _reminderScheduler.cancelMedicationAlarm(medId);
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể xóa mục tủ thuốc: $e'));
    }
  }

  @override
  Future<Result<void>> logWaterIntake({
    required String userId,
    required int deltaMl,
    int? targetWaterMl,
    String beverageLabel = 'Nước lọc',
    String? deleteEntryId,
  }) async {
    try {
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final docRef = _userRef(
        userId,
      ).collection('wellness_daily').doc(todayKey);
      final snap = await docRef.get();
      final existing = snap.data() ?? const <String, dynamic>{};
      final remRef = _userRef(
        userId,
      ).collection('medical_profiles').doc('hydration_reminder');
      final remDoc = await remRef.get();
      final remData = remDoc.data();

      final currentMl = (existing['waterMl'] as num?)?.toInt() ?? 0;
      final resolvedTarget =
          targetWaterMl ??
          (remData?['targetWaterMl'] as num?)?.toInt() ??
          (existing['targetWaterMl'] as num?)?.toInt() ??
          2000;

      final entries = <WaterIntakeLogEntry>[
        if (existing['entries'] is List)
          ...(existing['entries'] as List)
              .map(WaterIntakeLogEntry.fromMap)
              .whereType<WaterIntakeLogEntry>(),
      ]..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

      int nextMl;
      if (deleteEntryId != null) {
        final idx = entries.indexWhere((e) => e.id == deleteEntryId);
        final removedMl = idx >= 0 ? entries[idx].ml : deltaMl.abs();
        if (idx >= 0) entries.removeAt(idx);
        nextMl = (currentMl - removedMl).clamp(0, 10000);
      } else if (deltaMl > 0) {
        nextMl = (currentMl + deltaMl).clamp(0, 10000);
        entries.add(
          WaterIntakeLogEntry(
            id: 'cup_${_uuid.v4().substring(0, 8)}',
            ml: deltaMl,
            beverageLabel: beverageLabel.trim().isEmpty
                ? 'Nước lọc'
                : beverageLabel.trim(),
            loggedAt: DateTime.now(),
          ),
        );
      } else {
        nextMl = (currentMl + deltaMl).clamp(0, 10000);
        if (entries.isNotEmpty) {
          entries.removeLast();
        }
      }

      final nextLastCup = deltaMl > 0
          ? deltaMl
          : (entries.isNotEmpty
                ? entries.last.ml
                : ((existing['lastCupMl'] as num?)?.toInt() ?? 250));

      await docRef.set(<String, dynamic>{
        ...existing,
        'dateKey': todayKey,
        'waterMl': nextMl,
        'targetWaterMl': resolvedTarget,
        'lastCupMl': nextLastCup,
        'entries': entries.map((e) => e.toMap()).toList(),
      }, SetOptions(merge: true));

      if (remData != null) {
        if (deltaMl > 0 && remData['snoozedUntil'] != null) {
          await remRef.set(<String, dynamic>{
            'snoozedUntil': null,
          }, SetOptions(merge: true));
        }
        if (remData['reminderEnabled'] == true) {
          await _reminderScheduler.syncHydrationReminders(
            HydrationReminderStatusEntity(
              dayKey: todayKey,
              waterMl: nextMl,
              targetWaterMl: resolvedTarget,
              lastCupMl: nextLastCup,
              reminderEnabled: true,
              intervalMinutes:
                  (remData['intervalMinutes'] as num?)?.toInt() ?? 90,
              startHour: (remData['startHour'] as num?)?.toInt() ?? 7,
              startMinute: (remData['startMinute'] as num?)?.toInt() ?? 0,
              endHour: (remData['endHour'] as num?)?.toInt() ?? 21,
              endMinute: (remData['endMinute'] as num?)?.toInt() ?? 0,
              preferredCupMl:
                  ((remData['preferredCupMl'] as num?)?.toInt() ?? 250).clamp(
                    100,
                    600,
                  ),
              todayEntries: entries,
            ),
          );
        }
      }

      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể lưu lượng nước uống: $e'),
      );
    }
  }

  @override
  Future<Result<void>> saveHydrationReminderSettings({
    required String userId,
    required bool reminderEnabled,
    required int intervalMinutes,
    required int startHour,
    int startMinute = 0,
    required int endHour,
    int endMinute = 0,
    required int targetWaterMl,
    double? weightKg,
    double? heightCm,
    HydrationActivityLevel? activityLevel,
    bool? autoSyncTargetByBody,
    int? preferredCupMl,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
  }) async {
    try {
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final remRef = _userRef(
        userId,
      ).collection('medical_profiles').doc('hydration_reminder');
      final prevSnap = await remRef.get();
      final prev = prevSnap.data() ?? const <String, dynamic>{};

      final resolvedWeight =
          weightKg ?? (prev['weightKg'] as num?)?.toDouble() ?? 63.0;
      final resolvedHeight =
          heightCm ?? (prev['heightCm'] as num?)?.toDouble() ?? 168.0;
      final resolvedActivity =
          activityLevel ??
          HydrationActivityLevel.fromName(prev['activityLevel'] as String?);
      final resolvedAutoSync =
          autoSyncTargetByBody ?? (prev['autoSyncTargetByBody'] != false);
      final resolvedCup =
          (preferredCupMl ?? (prev['preferredCupMl'] as num?)?.toInt() ?? 250)
              .clamp(100, 600);
      final resolvedSnooze = clearSnooze
          ? null
          : (snoozedUntil ??
                (prev['snoozedUntil'] != null
                    ? DateTime.tryParse(prev['snoozedUntil'].toString())
                    : null));

      await remRef.set(<String, dynamic>{
        'reminderEnabled': reminderEnabled,
        'intervalMinutes': intervalMinutes,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'targetWaterMl': targetWaterMl,
        'weightKg': resolvedWeight,
        'heightCm': resolvedHeight,
        'activityLevel': resolvedActivity.name,
        'autoSyncTargetByBody': resolvedAutoSync,
        'preferredCupMl': resolvedCup,
        'snoozedUntil': resolvedSnooze?.toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      final dailyRef = _userRef(
        userId,
      ).collection('wellness_daily').doc(todayKey);
      final dailySnap = await dailyRef.get();
      final currentWater = (dailySnap.data()?['waterMl'] as num?)?.toInt() ?? 0;
      await dailyRef.set(<String, dynamic>{
        'dateKey': todayKey,
        'targetWaterMl': targetWaterMl,
      }, SetOptions(merge: true));

      await _reminderScheduler.syncHydrationReminders(
        HydrationReminderStatusEntity(
          dayKey: todayKey,
          waterMl: currentWater,
          targetWaterMl: targetWaterMl,
          reminderEnabled: reminderEnabled,
          intervalMinutes: intervalMinutes,
          startHour: startHour,
          startMinute: startMinute,
          endHour: endHour,
          endMinute: endMinute,
          weightKg: resolvedWeight,
          heightCm: resolvedHeight,
          activityLevel: resolvedActivity,
          autoSyncTargetByBody: resolvedAutoSync,
          preferredCupMl: resolvedCup,
          snoozedUntil: resolvedSnooze,
        ),
      );
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể lưu lịch nhắc uống nước: $e'),
      );
    }
  }

  @override
  Future<Result<void>> snoozeHydrationReminder({
    required String userId,
    required HydrationReminderStatusEntity status,
    int minutes = 15,
  }) async {
    try {
      final safeMins = minutes.clamp(5, 120);
      final until = DateTime.now().add(Duration(minutes: safeMins));
      await _userRef(
        userId,
      ).collection('medical_profiles').doc('hydration_reminder').set(
        <String, dynamic>{
          'reminderEnabled': true,
          'snoozedUntil': until.toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );
      final updatedStatus = HydrationReminderStatusEntity(
        dayKey: status.dayKey,
        waterMl: status.waterMl,
        targetWaterMl: status.targetWaterMl,
        lastCupMl: status.lastCupMl,
        reminderEnabled: true,
        intervalMinutes: status.intervalMinutes,
        startHour: status.startHour,
        startMinute: status.startMinute,
        endHour: status.endHour,
        endMinute: status.endMinute,
        weightKg: status.weightKg,
        heightCm: status.heightCm,
        activityLevel: status.activityLevel,
        autoSyncTargetByBody: status.autoSyncTargetByBody,
        preferredCupMl: status.preferredCupMl,
        snoozedUntil: until,
        todayEntries: status.todayEntries,
      );
      await _reminderScheduler.syncHydrationReminders(updatedStatus);
      await _reminderScheduler.snoozeWaterReminder(
        updatedStatus,
        minutes: safeMins,
      );
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể dời chuông nhắc uống nước: $e'),
      );
    }
  }

  @override
  Future<Result<int>> syncQueuedBackgroundHealthActions({
    required String userId,
  }) async {
    try {
      final actions = await NativeAlarmSchedulerBridge.instance
          .drainBackgroundHealthActions();
      if (actions.isEmpty) return const Success(0);

      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      var processed = 0;

      for (final act in actions) {
        final actDayKey = DateFormat('yyyy-MM-dd').format(act.loggedAt);
        if (act.type == 'water_logged' && act.ml > 0) {
          if (actDayKey == todayKey) {
            final res = await logWaterIntake(
              userId: userId,
              deltaMl: act.ml,
              beverageLabel: 'Từ thông báo',
            );
            res.fold((_) {}, (_) => processed++);
          } else {
            final docRef = _userRef(
              userId,
            ).collection('wellness_daily').doc(actDayKey);
            final snap = await docRef.get();
            final existing = snap.data() ?? const <String, dynamic>{};
            final currentMl = (existing['waterMl'] as num?)?.toInt() ?? 0;
            final entries = <WaterIntakeLogEntry>[
              if (existing['entries'] is List)
                ...(existing['entries'] as List)
                    .map(WaterIntakeLogEntry.fromMap)
                    .whereType<WaterIntakeLogEntry>(),
              WaterIntakeLogEntry(
                id: 'cup_${_uuid.v4().substring(0, 8)}',
                ml: act.ml,
                beverageLabel: 'Từ thông báo',
                loggedAt: act.loggedAt,
              ),
            ];
            await docRef.set(<String, dynamic>{
              ...existing,
              'dateKey': actDayKey,
              'waterMl': (currentMl + act.ml).clamp(0, 10000),
              'lastCupMl': act.ml,
              'entries': entries.map((e) => e.toMap()).toList(),
            }, SetOptions(merge: true));
            processed++;
          }
        } else if (act.type == 'med_taken' && act.medId.isNotEmpty) {
          final medRef = _userRef(
            userId,
          ).collection('medications').doc(act.medId);
          final medSnap = await medRef.get();
          final d = medSnap.data();
          if (medSnap.exists && d != null) {
            final prevTaken = d['lastTakenDayKey'] as String?;
            if (prevTaken != actDayKey) {
              final remPills = (d['remainingPills'] as num?)?.toInt() ?? 0;
              final nextRemaining = remPills > 0 ? remPills - 1 : 0;
              await medRef.update({
                'lastTakenDayKey': actDayKey,
                'remainingPills': nextRemaining,
              });
              final slot = MedicationScheduleSlot.fromName(
                d['slot'] as String?,
              );
              final updatedEntity = MedicationCabinetItemEntity(
                id: medSnap.id,
                ownerId: userId,
                name: (d['name'] ?? 'Thuốc / Vitamin') as String,
                dosage: (d['dosage'] ?? '1 viên') as String,
                slot: slot,
                remainingPills: nextRemaining,
                expiryDate:
                    DateTime.tryParse((d['expiryDate'] ?? '') as String) ??
                    DateTime.now().add(const Duration(days: 180)),
                lastTakenDayKey: actDayKey,
                memberName: (d['memberName'] ?? 'Cả gia đình') as String,
                reminderEnabled: d['reminderEnabled'] is bool
                    ? d['reminderEnabled'] as bool
                    : slot.isScheduledDaily,
                reminderHour:
                    (d['reminderHour'] as num?)?.toInt() ?? slot.defaultHour,
                reminderMinute:
                    (d['reminderMinute'] as num?)?.toInt() ??
                    slot.defaultMinute,
              );
              await _reminderScheduler.syncMedicationAlarm(
                updatedEntity,
                todayKey: todayKey,
              );
              processed++;
            }
          }
        }
      }
      return Success(processed);
    } catch (e) {
      return Err(
        UnexpectedFailure(
          message: 'Không thể đồng bộ thao tác thông báo nền: $e',
        ),
      );
    }
  }

  @override
  Future<Result<bool>> sendTestHydrationNotification({
    required HydrationReminderStatusEntity status,
    int delaySeconds = 0,
  }) async {
    try {
      final ok = await _reminderScheduler.sendTestWaterNotification(
        status,
        delaySeconds: delaySeconds,
      );
      return Success(ok);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể gửi thông báo thử nghiệm: $e'),
      );
    }
  }

  @override
  Future<Result<void>> addHealthVitalLog({
    required String userId,
    required double weightKg,
    required double heightCm,
    required int systolicMmHg,
    required int diastolicMmHg,
    required int heartRateBpm,
    required double sleepHours,
    String note = '',
  }) async {
    try {
      final id = 'vital_${_uuid.v4().substring(0, 8)}';
      await _userRef(userId).collection('health_logs').doc(id).set({
        'id': id,
        'ownerId': userId,
        'weightKg': weightKg,
        'heightCm': heightCm,
        'systolicMmHg': systolicMmHg,
        'diastolicMmHg': diastolicMmHg,
        'heartRateBpm': heartRateBpm,
        'sleepHours': sleepHours,
        'recordedAt': DateTime.now().toIso8601String(),
        'note': note.trim(),
      });

      // Keep hydration body profile synced when autoSyncTargetByBody is active
      final remRef = _userRef(
        userId,
      ).collection('medical_profiles').doc('hydration_reminder');
      final remSnap = await remRef.get();
      final remData = remSnap.data();
      final autoSync = remData == null || remData['autoSyncTargetByBody'] != false;
      final activity = HydrationActivityLevel.fromName(
        remData?['activityLevel'] as String?,
      );
      final recomputedTarget =
          AsianHealthBmiTdeeEngine.computeRecommendedWaterMl(
            weightKg: weightKg,
            heightCm: heightCm,
            activityLevel: activity,
          );
      await remRef.set(<String, dynamic>{
        'weightKg': weightKg,
        'heightCm': heightCm,
        if (autoSync) 'targetWaterMl': recomputedTarget,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      if (autoSync) {
        final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
        await _userRef(
          userId,
        ).collection('wellness_daily').doc(todayKey).set(<String, dynamic>{
          'dateKey': todayKey,
          'targetWaterMl': recomputedTarget,
        }, SetOptions(merge: true));
      }

      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể lưu chỉ số sức khỏe: $e'),
      );
    }
  }

  @override
  Future<Result<void>> saveEmergencyMedicalCard({
    required EmergencyMedicalCardEntity card,
  }) async {
    try {
      await _userRef(
        card.ownerId,
      ).collection('medical_profiles').doc('emergency_card').set({
        'ownerId': card.ownerId,
        'bloodType': card.bloodType.trim(),
        'allergies': card.allergies.trim(),
        'chronicConditions': card.chronicConditions.trim(),
        'insuranceCode': card.insuranceCode.trim(),
        'emergencyContactName': card.emergencyContactName.trim(),
        'emergencyContactPhone': card.emergencyContactPhone.trim(),
        'preferredHospital': card.preferredHospital.trim(),
      });
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể lưu thẻ y tế khẩn cấp: $e'),
      );
    }
  }

  @override
  Future<Result<void>> addGroceryItem({
    required String userId,
    required String name,
    required String quantityLabel,
    required GroceryAisle aisle,
    required int estimatedMinor,
    bool inFridgeStorage = false,
    DateTime? expiryDate,
  }) async {
    try {
      final id = 'groc_${_uuid.v4().substring(0, 8)}';
      await _userRef(userId).collection('grocery_items').doc(id).set({
        'id': id,
        'ownerId': userId,
        'name': name.trim(),
        'quantityLabel': quantityLabel.trim(),
        'aisle': aisle.name,
        'estimatedMinor': estimatedMinor,
        'isBought': false,
        'inFridgeStorage': inFridgeStorage,
        'expiryDate': expiryDate?.toIso8601String(),
      });
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể thêm món vào giỏ chợ: $e'),
      );
    }
  }

  @override
  Future<Result<void>> seedMealComboIngredients({
    required String userId,
    required MealComboPreset combo,
    required String dayKey,
  }) async {
    try {
      final batch = _firestore.batch();
      final mealRef = _userRef(userId).collection('meal_plans').doc(dayKey);
      batch.set(mealRef, {
        'dayKey': dayKey,
        'ownerId': userId,
        'breakfast': combo.breakfast,
        'lunch': combo.lunch,
        'dinner': combo.dinner,
        'estimatedDailyCostMinor': combo.estimatedCostMinor,
        'estimatedKcal': combo.estimatedKcal,
      });

      final grocCol = _userRef(userId).collection('grocery_items');
      for (final ing in combo.ingredients) {
        final id = 'groc_${_uuid.v4().substring(0, 8)}';
        batch.set(grocCol.doc(id), {
          'id': id,
          'ownerId': userId,
          'name': ing.name,
          'quantityLabel': ing.qty,
          'aisle': ing.aisle.name,
          'estimatedMinor': ing.priceMinor,
          'isBought': false,
          'inFridgeStorage': false,
          'expiryDate': null,
        });
      }
      await batch.commit();
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể áp dụng thực đơn: $e'));
    }
  }

  @override
  Future<Result<void>> toggleGroceryBought({
    required String userId,
    required SmartGroceryItemEntity item,
  }) async {
    try {
      await _userRef(userId).collection('grocery_items').doc(item.id).update({
        'isBought': !item.isBought,
      });
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể cập nhật giỏ chợ: $e'));
    }
  }

  @override
  Future<Result<void>> clearBoughtGroceries({required String userId}) async {
    try {
      final snap = await _userRef(
        userId,
      ).collection('grocery_items').where('isBought', isEqualTo: true).get();
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể dọn giỏ chợ đã mua: $e'),
      );
    }
  }

  @override
  Future<Result<void>> deleteGroceryItem({
    required String userId,
    required String itemId,
  }) async {
    try {
      await _userRef(userId).collection('grocery_items').doc(itemId).delete();
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể xóa thực phẩm: $e'));
    }
  }

  @override
  Future<Result<void>> saveUtilityReading({
    required String userId,
    required String monthKey,
    required int prevElectricKwh,
    required int currElectricKwh,
    required int prevWaterM3,
    required int currWaterM3,
    required bool useEvnTieredTariff,
    required int fixedServicesMinor,
    required int totalAmountMinor,
  }) async {
    try {
      final id = 'util_${monthKey}_${_uuid.v4().substring(0, 6)}';
      await _userRef(userId).collection('utility_readings').doc(id).set({
        'id': id,
        'ownerId': userId,
        'monthKey': monthKey,
        'prevElectricKwh': prevElectricKwh,
        'currElectricKwh': currElectricKwh,
        'prevWaterM3': prevWaterM3,
        'currWaterM3': currWaterM3,
        'useEvnTieredTariff': useEvnTieredTariff,
        'fixedServicesMinor': fixedServicesMinor,
        'totalAmountMinor': totalAmountMinor,
        'isPaid': false,
        'recordedAt': DateTime.now().toIso8601String(),
      });
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể lưu chỉ số điện nước: $e'),
      );
    }
  }

  @override
  Future<Result<void>> markUtilityReadingPaid({
    required String userId,
    required String readingId,
  }) async {
    try {
      await _userRef(
        userId,
      ).collection('utility_readings').doc(readingId).update({'isPaid': true});
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể cập nhật hóa đơn điện nước: $e'),
      );
    }
  }

  @override
  Future<Result<void>> saveHomeContract({
    required String userId,
    required String homeName,
    required int monthlyRentMinor,
    required int depositMinor,
    required int paymentDayOfMonth,
    required DateTime leaseEndDate,
    required String wifiCredentials,
    required String nextApplianceMaintenanceNote,
  }) async {
    try {
      const id = 'primary_home';
      await _userRef(userId).collection('home_contracts').doc(id).set({
        'id': id,
        'ownerId': userId,
        'homeName': homeName.trim(),
        'monthlyRentMinor': monthlyRentMinor,
        'depositMinor': depositMinor,
        'paymentDayOfMonth': paymentDayOfMonth,
        'leaseEndDate': leaseEndDate.toIso8601String(),
        'wifiCredentials': wifiCredentials.trim(),
        'nextApplianceMaintenanceNote': nextApplianceMaintenanceNote.trim(),
      });
      return const Success(null);
    } catch (e) {
      return Err(
        UnexpectedFailure(message: 'Không thể lưu thông tin nhà cửa: $e'),
      );
    }
  }

  @override
  Future<Result<void>> addOrUpdateNote({
    required String userId,
    String? existingId,
    required String title,
    required String content,
    required String categoryTag,
    LifeMoodLevel? mood,
    bool isPinned = false,
  }) async {
    try {
      final id = existingId ?? 'note_${_uuid.v4().substring(0, 8)}';
      await _userRef(userId).collection('life_notes').doc(id).set({
        'id': id,
        'ownerId': userId,
        'title': title.trim(),
        'content': content.trim(),
        'categoryTag': categoryTag.trim(),
        'mood': mood?.name,
        'isPinned': isPinned,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể lưu ghi chú: $e'));
    }
  }

  @override
  Future<Result<void>> toggleNotePinned({
    required String userId,
    required SmartLifeNoteEntity note,
  }) async {
    try {
      await _userRef(userId).collection('life_notes').doc(note.id).update({
        'isPinned': !note.isPinned,
      });
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể ghim ghi chú: $e'));
    }
  }

  @override
  Future<Result<void>> deleteNote({
    required String userId,
    required String noteId,
  }) async {
    try {
      await _userRef(userId).collection('life_notes').doc(noteId).delete();
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể xóa ghi chú: $e'));
    }
  }
}
