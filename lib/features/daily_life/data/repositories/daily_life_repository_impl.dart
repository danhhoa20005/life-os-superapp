import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/daily_life_entities.dart';
import '../../domain/repositories/daily_life_repository.dart';

class DailyLifeRepositoryImpl implements DailyLifeRepository {
  final FirebaseFirestore _firestore;
  static const Uuid _uuid = Uuid();

  const DailyLifeRepositoryImpl(this._firestore);

  DocumentReference<Map<String, dynamic>> _userRef(String userId) =>
      _firestore.collection('users').doc(userId);

  @override
  Stream<DailyLifeSnapshot> watchAll({required String userId}) {
    return Stream<DailyLifeSnapshot>.multi((controller) {
      var meds = <MedicationCabinetItemEntity>[];
      var healthLogs = <HealthVitalLogEntity>[];
      var emergencyCard = EmergencyMedicalCardEntity(ownerId: userId);
      var groceries = <SmartGroceryItemEntity>[];
      var mealPlans = <DailyMealPlanEntity>[];
      var readings = <UtilityMeterReadingEntity>[];
      var contracts = <HomeContractMaintenanceEntity>[];
      var notes = <SmartLifeNoteEntity>[];

      void emitNow() {
        if (controller.isClosed) return;
        controller.add(
          DailyLifeSnapshot(
            medications: meds,
            healthLogs: healthLogs,
            emergencyCard: emergencyCard,
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
              return MedicationCabinetItemEntity(
                id: doc.id,
                ownerId: userId,
                name: (d['name'] ?? 'Thuốc / Vitamin') as String,
                dosage: (d['dosage'] ?? '1 viên') as String,
                slot: MedicationScheduleSlot.fromName(d['slot'] as String?),
                remainingPills: (d['remainingPills'] as num?)?.toInt() ?? 0,
                expiryDate:
                    DateTime.tryParse((d['expiryDate'] ?? '') as String) ??
                    DateTime.now().add(const Duration(days: 180)),
                lastTakenDayKey: d['lastTakenDayKey'] as String?,
                memberName: (d['memberName'] ?? 'Cả gia đình') as String,
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
    String memberName = 'Cả gia đình',
  }) async {
    try {
      final id = 'med_${_uuid.v4().substring(0, 8)}';
      await _userRef(userId).collection('medications').doc(id).set({
        'id': id,
        'ownerId': userId,
        'name': name.trim(),
        'dosage': dosage.trim(),
        'slot': slot.name,
        'remainingPills': remainingPills,
        'expiryDate': expiryDate.toIso8601String(),
        'lastTakenDayKey': null,
        'memberName': memberName.trim(),
      });
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể lưu thuốc/vitamin: $e'));
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
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể xóa mục tủ thuốc: $e'));
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
