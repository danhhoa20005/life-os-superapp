import 'package:equatable/equatable.dart';
import '../../../../core/security/bank_notification_parser.dart';

enum VehicleDueState { healthy, dueSoon, overdue }

class VehicleEntity extends Equatable {
  final String id;
  final String ownerId;
  final String? familyId;
  final bool isFamilyShared;
  final String name;
  final String plateNumber;
  final bool maskPlateWhenShared;
  final int currentOdometerKm;
  final int lastServiceOdometerKm;
  final DateTime lastServiceDate;
  final int serviceIntervalKm;
  final int serviceIntervalDays;
  final DateTime? insuranceExpiryDate;
  final DateTime? inspectionExpiryDate;

  const VehicleEntity({
    required this.id,
    required this.ownerId,
    this.familyId,
    required this.isFamilyShared,
    required this.name,
    required this.plateNumber,
    this.maskPlateWhenShared = true,
    required this.currentOdometerKm,
    required this.lastServiceOdometerKm,
    required this.lastServiceDate,
    this.serviceIntervalKm = 3000,
    this.serviceIntervalDays = 90,
    this.insuranceExpiryDate,
    this.inspectionExpiryDate,
  });

  String displayPlateForViewer(String viewerUserId) {
    if (!isFamilyShared || viewerUserId == ownerId || !maskPlateWhenShared) {
      return plateNumber;
    }
    return OtpRedactor.maskLicensePlate(plateNumber);
  }

  int get nextDueKm => lastServiceOdometerKm + serviceIntervalKm;

  DateTime get nextDueDate =>
      lastServiceDate.add(Duration(days: serviceIntervalDays));

  int get remainingKm => nextDueKm - currentOdometerKm;

  int remainingDaysFrom(DateTime now) => nextDueDate.difference(now).inDays;

  /// Evaluates `min(km due, date due)` per Section 8.2 & Section 17 of Life OS specification.
  VehicleDueState dueStateAt(
    DateTime now, {
    int warnKm = 300,
    int warnDays = 7,
  }) {
    final remDays = remainingDaysFrom(now);
    if (remainingKm <= 0 || remDays <= 0) {
      return VehicleDueState.overdue;
    }
    if (remainingKm <= warnKm || remDays <= warnDays) {
      return VehicleDueState.dueSoon;
    }
    return VehicleDueState.healthy;
  }

  @override
  List<Object?> get props => [
    id,
    ownerId,
    familyId,
    isFamilyShared,
    name,
    plateNumber,
    maskPlateWhenShared,
    currentOdometerKm,
    lastServiceOdometerKm,
    lastServiceDate,
    serviceIntervalKm,
    serviceIntervalDays,
    insuranceExpiryDate,
    inspectionExpiryDate,
  ];
}

class RecurringBillEntity extends Equatable {
  final String id;
  final String ownerId;
  final String? familyId;
  final String title;
  final String providerName;
  final int estimatedAmountMinor;
  final DateTime nextDueDate;
  final int? lastPaidAmountMinor;
  final int? averagePaidMinor;
  final int paymentCount;

  const RecurringBillEntity({
    required this.id,
    required this.ownerId,
    this.familyId,
    required this.title,
    required this.providerName,
    required this.estimatedAmountMinor,
    required this.nextDueDate,
    this.lastPaidAmountMinor,
    this.averagePaidMinor,
    this.paymentCount = 0,
  });

  /// Detects abnormal bill spike (>= 25% higher than historical average) when history exists.
  bool get hasAbnormalSpike {
    if (paymentCount < 2 ||
        averagePaidMinor == null ||
        averagePaidMinor! <= 0 ||
        lastPaidAmountMinor == null) {
      return false;
    }
    return lastPaidAmountMinor! >= (averagePaidMinor! * 1.25).round();
  }

  @override
  List<Object?> get props => [
    id,
    ownerId,
    familyId,
    title,
    providerName,
    estimatedAmountMinor,
    nextDueDate,
    lastPaidAmountMinor,
    averagePaidMinor,
    paymentCount,
  ];
}
