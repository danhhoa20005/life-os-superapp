import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../domain/entities/vehicle_entities.dart';
import '../../domain/repositories/vehicle_repository.dart';

class VehicleRemoteDataSource {
  final FirebaseFirestore _firestore;
  static const Uuid _uuid = Uuid();

  const VehicleRemoteDataSource(this._firestore);

  VehicleEntity _mapVehicle(
    DocumentSnapshot<Map<String, dynamic>> doc,
    bool isShared,
    String? familyId,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final lastDateRaw = d['lastServiceDate'];
    final insRaw = d['insuranceExpiryDate'];
    final inspRaw = d['inspectionExpiryDate'];
    final name = (d['name'] as String?) ?? 'Xe máy';
    final rawCat = d['category'] as String?;
    final rawProfileKey = d['modelProfileKey'] as String?;
    final resolvedProfile = MotorcycleSpecCatalog.resolveForVehicle(
      modelProfileKey: rawProfileKey,
      category: rawCat != null
          ? VehicleCategory.values.where((c) => c.name == rawCat).firstOrNull
          : null,
      vehicleName: name,
    );
    final category = rawCat != null
        ? (VehicleCategory.values.where((c) => c.name == rawCat).firstOrNull ??
              resolvedProfile.category)
        : resolvedProfile.category;

    final rawCompMap = d['componentLastKm'];
    final compMap = <String, int>{};
    if (rawCompMap is Map) {
      for (final entry in rawCompMap.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        if (v is num) {
          compMap[k] = v.toInt();
        }
      }
    }

    return VehicleEntity(
      id: (d['id'] as String?) ?? doc.id,
      ownerId: (d['ownerId'] as String?) ?? '',
      familyId: familyId,
      isFamilyShared: isShared,
      name: name,
      plateNumber: (d['plateNumber'] as String?) ?? '',
      category: category,
      modelProfileKey: rawProfileKey ?? resolvedProfile.profileKey,
      maskPlateWhenShared: (d['maskPlateWhenShared'] as bool?) ?? true,
      currentOdometerKm: (d['currentOdometerKm'] as num?)?.toInt() ?? 0,
      lastServiceOdometerKm: (d['lastServiceOdometerKm'] as num?)?.toInt() ?? 0,
      lastServiceDate: lastDateRaw is Timestamp
          ? lastDateRaw.toDate()
          : DateTime.now(),
      serviceIntervalKm:
          (d['serviceIntervalKm'] as num?)?.toInt() ??
          resolvedProfile.recommendedOilIntervalKm,
      serviceIntervalDays:
          (d['serviceIntervalDays'] as num?)?.toInt() ??
          resolvedProfile.recommendedIntervalDays,
      componentLastKm: Map<String, int>.unmodifiable(compMap),
      insuranceExpiryDate: insRaw is Timestamp ? insRaw.toDate() : null,
      inspectionExpiryDate: inspRaw is Timestamp ? inspRaw.toDate() : null,
    );
  }

  MaintenanceRecordEntity _mapMaintenanceRecord(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String vehicleId,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final dateRaw = d['serviceDate'];
    return MaintenanceRecordEntity(
      id: (d['id'] as String?) ?? doc.id,
      vehicleId: vehicleId,
      serviceTitle: (d['serviceTitle'] as String?) ?? 'Bảo dưỡng định kỳ',
      componentKey: d['componentKey'] as String?,
      odometerKm: (d['odometerKm'] as num?)?.toInt() ?? 0,
      costMinor: (d['costMinor'] as num?)?.toInt() ?? 0,
      serviceDate: dateRaw is Timestamp ? dateRaw.toDate() : DateTime.now(),
    );
  }

  RecurringBillEntity _mapBill(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String? familyId,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final dueRaw = d['nextDueDate'];
    return RecurringBillEntity(
      id: (d['id'] as String?) ?? doc.id,
      ownerId: (d['ownerId'] as String?) ?? '',
      familyId: familyId,
      title: (d['title'] as String?) ?? 'Hóa đơn',
      providerName: (d['providerName'] as String?) ?? '',
      estimatedAmountMinor: (d['estimatedAmountMinor'] as num?)?.toInt() ?? 0,
      nextDueDate: dueRaw is Timestamp ? dueRaw.toDate() : DateTime.now(),
      lastPaidAmountMinor: (d['lastPaidAmountMinor'] as num?)?.toInt(),
      averagePaidMinor: (d['averagePaidMinor'] as num?)?.toInt(),
      paymentCount: (d['paymentCount'] as num?)?.toInt() ?? 0,
    );
  }

  Stream<List<VehicleEntity>> watchVehicles({
    required String userId,
    String? familyId,
  }) {
    final privStream = _firestore
        .collection('users')
        .doc(userId)
        .collection('vehicles')
        .snapshots()
        .map((s) => s.docs.map((d) => _mapVehicle(d, false, null)).toList());

    if (familyId == null || familyId.isEmpty) return privStream;

    final famStream = _firestore
        .collection('families')
        .doc(familyId)
        .collection('vehicles')
        .snapshots()
        .map((s) => s.docs.map((d) => _mapVehicle(d, true, familyId)).toList());

    return StreamCombiner.combine2(
      privStream,
      famStream,
      (p, f) => <VehicleEntity>[...p, ...f],
    );
  }

  Stream<List<RecurringBillEntity>> watchBills({
    required String userId,
    String? familyId,
  }) {
    final privStream = _firestore
        .collection('users')
        .doc(userId)
        .collection('bills')
        .orderBy('nextDueDate')
        .snapshots()
        .map((s) => s.docs.map((d) => _mapBill(d, null)).toList());

    if (familyId == null || familyId.isEmpty) return privStream;

    final famStream = _firestore
        .collection('families')
        .doc(familyId)
        .collection('bills')
        .orderBy('nextDueDate')
        .snapshots()
        .map((s) => s.docs.map((d) => _mapBill(d, familyId)).toList());

    return StreamCombiner.combine2(
      privStream,
      famStream,
      (p, f) => <RecurringBillEntity>[...p, ...f],
    );
  }

  DocumentReference<Map<String, dynamic>> _vehicleRef(VehicleEntity v) {
    if (v.isFamilyShared && v.familyId != null && v.familyId!.isNotEmpty) {
      return _firestore
          .collection('families')
          .doc(v.familyId)
          .collection('vehicles')
          .doc(v.id);
    }
    return _firestore
        .collection('users')
        .doc(v.ownerId)
        .collection('vehicles')
        .doc(v.id);
  }

  Future<void> createVehicle({
    required String userId,
    String? familyId,
    required bool isFamilyShared,
    required String name,
    required String plateNumber,
    required int currentOdometerKm,
    required int serviceIntervalKm,
    required int serviceIntervalDays,
    VehicleCategory category = VehicleCategory.scooter,
    String? modelProfileKey,
    DateTime? insuranceExpiryDate,
    DateTime? inspectionExpiryDate,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final resolvedProfile = MotorcycleSpecCatalog.resolveForVehicle(
      modelProfileKey: modelProfileKey,
      category: category,
      vehicleName: name,
    );
    final ref = isFamilyShared && familyId != null && familyId.isNotEmpty
        ? _firestore
              .collection('families')
              .doc(familyId)
              .collection('vehicles')
              .doc(id)
        : _firestore
              .collection('users')
              .doc(userId)
              .collection('vehicles')
              .doc(id);

    final primaryKey = resolvedProfile.category == VehicleCategory.electricMoto
        ? 'ev_battery'
        : 'engine_oil';

    await ref.set({
      'id': id,
      'ownerId': userId,
      'name': name,
      'plateNumber': plateNumber,
      'category': resolvedProfile.category.name,
      'modelProfileKey': resolvedProfile.profileKey,
      'maskPlateWhenShared': true,
      'currentOdometerKm': currentOdometerKm,
      'lastServiceOdometerKm': currentOdometerKm,
      'lastServiceDate': Timestamp.fromDate(now),
      'serviceIntervalKm': serviceIntervalKm,
      'serviceIntervalDays': serviceIntervalDays,
      'componentLastKm': <String, int>{primaryKey: currentOdometerKm},
      if (insuranceExpiryDate != null)
        'insuranceExpiryDate': Timestamp.fromDate(insuranceExpiryDate),
      if (inspectionExpiryDate != null)
        'inspectionExpiryDate': Timestamp.fromDate(inspectionExpiryDate),
      'createdAt': Timestamp.fromDate(now),
    });
  }

  Future<void> updateVehicleSpecProfile({
    required VehicleEntity vehicle,
    required VehicleCategory category,
    required String modelProfileKey,
    DateTime? insuranceExpiryDate,
    DateTime? inspectionExpiryDate,
  }) async {
    final profile = MotorcycleSpecCatalog.resolveForVehicle(
      modelProfileKey: modelProfileKey,
      category: category,
      vehicleName: vehicle.name,
    );
    final payload = <String, dynamic>{
      'category': profile.category.name,
      'modelProfileKey': profile.profileKey,
      'serviceIntervalKm': profile.recommendedOilIntervalKm,
      'serviceIntervalDays': profile.recommendedIntervalDays,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
    if (insuranceExpiryDate != null) {
      payload['insuranceExpiryDate'] = Timestamp.fromDate(insuranceExpiryDate);
    }
    if (inspectionExpiryDate != null) {
      payload['inspectionExpiryDate'] = Timestamp.fromDate(
        inspectionExpiryDate,
      );
    }
    await _vehicleRef(vehicle).update(payload);
  }

  Future<void> updateOdometer({
    required VehicleEntity vehicle,
    required int newOdometerKm,
  }) async {
    await _vehicleRef(vehicle).update({
      'currentOdometerKm': newOdometerKm,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Stream<List<MaintenanceRecordEntity>> watchMaintenanceHistory({
    required VehicleEntity vehicle,
  }) {
    return _vehicleRef(vehicle)
        .collection('maintenances')
        .orderBy('serviceDate', descending: true)
        .limit(20)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => _mapMaintenanceRecord(d, vehicle.id))
              .toList(growable: false),
        );
  }

  Future<void> recordMaintenance({
    required VehicleEntity vehicle,
    required String serviceTitle,
    required int odometerKm,
    required int costMinor,
    String? componentKey,
    String? walletIdForExpense,
  }) async {
    final now = DateTime.now();
    final vRef = _vehicleRef(vehicle);
    final mId = _uuid.v4();
    final normalizedKey = componentKey != null && componentKey.trim().isNotEmpty
        ? componentKey.trim()
        : null;
    final resetsPrimaryOilCycle =
        normalizedKey == null ||
        normalizedKey == 'engine_oil' ||
        normalizedKey == 'ev_battery';

    await _firestore.runTransaction((tx) async {
      DocumentSnapshot<Map<String, dynamic>>? walletSnap;
      DocumentReference<Map<String, dynamic>>? walletRef;
      if (costMinor > 0 &&
          walletIdForExpense != null &&
          walletIdForExpense.isNotEmpty) {
        walletRef = _firestore
            .collection('users')
            .doc(vehicle.ownerId)
            .collection('wallets')
            .doc(walletIdForExpense);
        walletSnap = await tx.get(walletRef);
      }

      final updatedKm = odometerKm > vehicle.currentOdometerKm
          ? odometerKm
          : vehicle.currentOdometerKm;

      tx.set(vRef.collection('maintenances').doc(mId), {
        'id': mId,
        'serviceTitle': serviceTitle,
        if (normalizedKey != null) 'componentKey': normalizedKey,
        'odometerKm': odometerKm,
        'costMinor': costMinor,
        'serviceDate': Timestamp.fromDate(now),
      });

      final targetKey =
          normalizedKey ??
          (vehicle.maintenanceProfile.category == VehicleCategory.electricMoto
              ? 'ev_battery'
              : 'engine_oil');

      final vehicleUpdate = <String, dynamic>{
        'currentOdometerKm': updatedKm,
        'componentLastKm.$targetKey': odometerKm,
        'updatedAt': Timestamp.fromDate(now),
      };
      if (resetsPrimaryOilCycle) {
        vehicleUpdate['lastServiceOdometerKm'] = odometerKm;
        vehicleUpdate['lastServiceDate'] = Timestamp.fromDate(now);
      }
      tx.update(vRef, vehicleUpdate);

      if (walletRef != null &&
          walletSnap != null &&
          walletSnap.exists &&
          costMinor > 0) {
        final bal = (walletSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
        final txId = 'maint_$mId';
        final txRef = _firestore
            .collection('users')
            .doc(vehicle.ownerId)
            .collection('transactions')
            .doc(txId);
        final monthKey =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

        tx.update(walletRef, {
          'balanceMinor': bal - costMinor,
          'updatedAt': Timestamp.fromDate(now),
        });
        tx.set(txRef, {
          'id': txId,
          'ownerId': vehicle.ownerId,
          'walletId': walletIdForExpense,
          'categoryName': 'Xe cộ & Di chuyển',
          'kind': 'expense',
          'direction': 'debit',
          'amountMinor': costMinor,
          'currencyCode': 'VND',
          'merchant': '${vehicle.name} — $serviceTitle',
          'occurredAt': Timestamp.fromDate(now),
          'monthKey': monthKey,
          'sourceKind': 'manual',
          'verification': 'userConfirmed',
          'crossSourceFingerprint':
              BankNotificationParser.computeCrossSourceFingerprint(
                ownerId: vehicle.ownerId,
                direction: 'debit',
                amountMinor: costMinor,
                occurredAt: now,
              ),
          'isVehicleMaintenanceHint': false,
          'schemaVersion': 1,
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        });
      }
    });
  }

  Future<void> createRecurringBill({
    required String userId,
    String? familyId,
    required String title,
    required String providerName,
    required int estimatedAmountMinor,
    required DateTime nextDueDate,
  }) async {
    final id = _uuid.v4();
    final ref = familyId != null && familyId.isNotEmpty
        ? _firestore
              .collection('families')
              .doc(familyId)
              .collection('bills')
              .doc(id)
        : _firestore
              .collection('users')
              .doc(userId)
              .collection('bills')
              .doc(id);

    await ref.set({
      'id': id,
      'ownerId': userId,
      'title': title,
      'providerName': providerName,
      'estimatedAmountMinor': estimatedAmountMinor,
      'nextDueDate': Timestamp.fromDate(nextDueDate),
      'paymentCount': 0,
      'createdAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<bool> payRecurringBill({
    required String userId,
    required RecurringBillEntity bill,
    required int paidAmountMinor,
    required String walletId,
  }) async {
    final billRef = bill.familyId != null && bill.familyId!.isNotEmpty
        ? _firestore
              .collection('families')
              .doc(bill.familyId)
              .collection('bills')
              .doc(bill.id)
        : _firestore
              .collection('users')
              .doc(userId)
              .collection('bills')
              .doc(bill.id);
    final walletRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('wallets')
        .doc(walletId);
    var spikeDetected = false;

    await _firestore.runTransaction((tx) async {
      final wSnap = await tx.get(walletRef);
      if (!wSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy ví thanh toán.',
        );
      }
      final prevAvg = bill.averagePaidMinor ?? bill.estimatedAmountMinor;
      if (bill.paymentCount >= 1 &&
          paidAmountMinor >= (prevAvg * 1.25).round()) {
        spikeDetected = true;
      }

      final newCount = bill.paymentCount + 1;
      final newAvg =
          (((bill.averagePaidMinor ?? paidAmountMinor) * bill.paymentCount) +
              paidAmountMinor) ~/
          newCount;
      final nextDue = DateTime(
        bill.nextDueDate.year,
        bill.nextDueDate.month + 1,
        bill.nextDueDate.day,
      );
      final now = DateTime.now();
      final bal = (wSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;

      tx.update(walletRef, {
        'balanceMinor': bal - paidAmountMinor,
        'updatedAt': Timestamp.fromDate(now),
      });

      tx.update(billRef, {
        'lastPaidAmountMinor': paidAmountMinor,
        'averagePaidMinor': newAvg,
        'paymentCount': newCount,
        'nextDueDate': Timestamp.fromDate(nextDue),
      });

      final txId = 'bill_${bill.id}_${now.millisecondsSinceEpoch}';
      final txRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('transactions')
          .doc(txId);
      final monthKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

      tx.set(txRef, {
        'id': txId,
        'ownerId': userId,
        'walletId': walletId,
        'categoryName': 'Điện/Nước/Internet',
        'kind': 'expense',
        'direction': 'debit',
        'amountMinor': paidAmountMinor,
        'currencyCode': 'VND',
        'merchant': bill.title,
        'occurredAt': Timestamp.fromDate(now),
        'monthKey': monthKey,
        'sourceKind': 'manual',
        'verification': 'userConfirmed',
        'crossSourceFingerprint':
            BankNotificationParser.computeCrossSourceFingerprint(
              ownerId: userId,
              direction: 'debit',
              amountMinor: paidAmountMinor,
              occurredAt: now,
            ),
        'schemaVersion': 1,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    });

    return spikeDetected;
  }
}

class VehicleRepositoryImpl implements VehicleRepository {
  final VehicleRemoteDataSource _remoteDataSource;
  const VehicleRepositoryImpl(this._remoteDataSource);

  @override
  Stream<Result<List<VehicleEntity>>> watchVehicles({
    required String userId,
    String? familyId,
  }) {
    return _remoteDataSource
        .watchVehicles(userId: userId, familyId: familyId)
        .map<Result<List<VehicleEntity>>>((v) => Success(v))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<VehicleEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Stream<Result<List<RecurringBillEntity>>> watchRecurringBills({
    required String userId,
    String? familyId,
  }) {
    return _remoteDataSource
        .watchBills(userId: userId, familyId: familyId)
        .map<Result<List<RecurringBillEntity>>>((b) => Success(b))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<RecurringBillEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Future<Result<void>> createVehicle({
    required String userId,
    String? familyId,
    required bool isFamilyShared,
    required String name,
    required String plateNumber,
    required int currentOdometerKm,
    required int serviceIntervalKm,
    required int serviceIntervalDays,
    VehicleCategory category = VehicleCategory.scooter,
    String? modelProfileKey,
    DateTime? insuranceExpiryDate,
    DateTime? inspectionExpiryDate,
  }) async {
    try {
      await _remoteDataSource.createVehicle(
        userId: userId,
        familyId: familyId,
        isFamilyShared: isFamilyShared,
        name: name,
        plateNumber: plateNumber,
        currentOdometerKm: currentOdometerKm,
        serviceIntervalKm: serviceIntervalKm,
        serviceIntervalDays: serviceIntervalDays,
        category: category,
        modelProfileKey: modelProfileKey,
        insuranceExpiryDate: insuranceExpiryDate,
        inspectionExpiryDate: inspectionExpiryDate,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> updateVehicleSpecProfile({
    required VehicleEntity vehicle,
    required VehicleCategory category,
    required String modelProfileKey,
    DateTime? insuranceExpiryDate,
    DateTime? inspectionExpiryDate,
  }) async {
    try {
      await _remoteDataSource.updateVehicleSpecProfile(
        vehicle: vehicle,
        category: category,
        modelProfileKey: modelProfileKey,
        insuranceExpiryDate: insuranceExpiryDate,
        inspectionExpiryDate: inspectionExpiryDate,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> updateOdometer({
    required VehicleEntity vehicle,
    required int newOdometerKm,
  }) async {
    try {
      await _remoteDataSource.updateOdometer(
        vehicle: vehicle,
        newOdometerKm: newOdometerKm,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Stream<Result<List<MaintenanceRecordEntity>>> watchMaintenanceHistory({
    required VehicleEntity vehicle,
  }) {
    return _remoteDataSource
        .watchMaintenanceHistory(vehicle: vehicle)
        .map<Result<List<MaintenanceRecordEntity>>>((r) => Success(r))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<MaintenanceRecordEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Future<Result<void>> recordMaintenance({
    required VehicleEntity vehicle,
    required String serviceTitle,
    required int odometerKm,
    required int costMinor,
    String? componentKey,
    String? walletIdForExpense,
  }) async {
    try {
      await _remoteDataSource.recordMaintenance(
        vehicle: vehicle,
        serviceTitle: serviceTitle,
        odometerKm: odometerKm,
        costMinor: costMinor,
        componentKey: componentKey,
        walletIdForExpense: walletIdForExpense,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> createRecurringBill({
    required String userId,
    String? familyId,
    required String title,
    required String providerName,
    required int estimatedAmountMinor,
    required DateTime nextDueDate,
  }) async {
    try {
      await _remoteDataSource.createRecurringBill(
        userId: userId,
        familyId: familyId,
        title: title,
        providerName: providerName,
        estimatedAmountMinor: estimatedAmountMinor,
        nextDueDate: nextDueDate,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<bool>> payRecurringBill({
    required String userId,
    required RecurringBillEntity bill,
    required int paidAmountMinor,
    required String walletId,
  }) async {
    try {
      final spike = await _remoteDataSource.payRecurringBill(
        userId: userId,
        bill: bill,
        paidAmountMinor: paidAmountMinor,
        walletId: walletId,
      );
      return Success(spike);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
