import 'dart:math' as math;

import 'package:equatable/equatable.dart';

class FuelOrChargeLog extends Equatable {
  final String id;
  final String vehicleId;
  final int odometerKm;
  final double litersOrKwh; // Liters for ICE, kWh for EV
  final int costMinor;
  final bool isFullTank;
  final DateTime loggedAt;

  const FuelOrChargeLog({
    required this.id,
    required this.vehicleId,
    required this.odometerKm,
    required this.litersOrKwh,
    required this.costMinor,
    this.isFullTank = true,
    required this.loggedAt,
  });

  @override
  List<Object?> get props => [
    id,
    vehicleId,
    odometerKm,
    litersOrKwh,
    costMinor,
    isFullTank,
    loggedAt,
  ];
}

class VerifiedVehicleModelSpec extends Equatable {
  final String specId;
  final String brand;
  final String modelName;
  final String variant;
  final String yearRange;
  final bool isElectric;
  final bool requiresPeriodicInspection;
  final int? verifiedOilIntervalKm;
  final int? verifiedPeriodicServiceKm;
  final String sourceReference;

  const VerifiedVehicleModelSpec({
    required this.specId,
    required this.brand,
    required this.modelName,
    required this.variant,
    required this.yearRange,
    this.isElectric = false,
    this.requiresPeriodicInspection = false,
    this.verifiedOilIntervalKm,
    this.verifiedPeriodicServiceKm,
    required this.sourceReference,
  });

  @override
  List<Object?> get props => [
    specId,
    brand,
    modelName,
    variant,
    yearRange,
    isElectric,
    requiresPeriodicInspection,
    verifiedOilIntervalKm,
    verifiedPeriodicServiceKm,
    sourceReference,
  ];
}

class VehicleOwnershipAnalytics extends Equatable {
  final String vehicleId;
  final int totalFuelCostMinor;
  final int totalMaintenanceAndRepairMinor;
  final int totalInsuranceAndInspectionMinor;
  final int totalCostOfOwnershipMinor;
  final int trackedDistanceKm;
  final int? costPerKmMinor;
  final double? consumptionPer100Km; // L/100km or kWh/100km
  final double? averageDailyKm;
  final DateTime? predictedNextOilDueDate;

  const VehicleOwnershipAnalytics({
    required this.vehicleId,
    required this.totalFuelCostMinor,
    required this.totalMaintenanceAndRepairMinor,
    required this.totalInsuranceAndInspectionMinor,
    required this.totalCostOfOwnershipMinor,
    required this.trackedDistanceKm,
    this.costPerKmMinor,
    this.consumptionPer100Km,
    this.averageDailyKm,
    this.predictedNextOilDueDate,
  });

  @override
  List<Object?> get props => [
    vehicleId,
    totalFuelCostMinor,
    totalMaintenanceAndRepairMinor,
    totalInsuranceAndInspectionMinor,
    totalCostOfOwnershipMinor,
    trackedDistanceKm,
    costPerKmMinor,
    consumptionPer100Km,
    averageDailyKm,
    predictedNextOilDueDate,
  ];
}

/// Vehicle Intelligence, Fuel Efficiency, Cost-per-Km (`₫/km` TCO) & Verified OEM Spec Catalog (Section 25).
///
/// Strict Safety Rule:
/// - Never fabricates maintenance schedules for vehicle models missing verified OEM documentation
///   (`lookupVerifiedSpec` returns `null` when unverified so the UI prompts manual interval entry).
abstract final class VehicleIntelligenceEngine {
  static const List<VerifiedVehicleModelSpec> verifiedCatalog = [
    VerifiedVehicleModelSpec(
      specId: 'honda_vision_110_2021_2026',
      brand: 'Honda',
      modelName: 'Vision 110',
      variant: 'Tiêu chuẩn / Cao cấp / Thể thao (eSP)',
      yearRange: '2021–2026',
      verifiedOilIntervalKm: 2000,
      verifiedPeriodicServiceKm: 4000,
      sourceReference: 'Sổ bảo hành Honda Việt Nam (eSP 110cc)',
    ),
    VerifiedVehicleModelSpec(
      specId: 'honda_airblade_125_160_2020_2026',
      brand: 'Honda',
      modelName: 'Air Blade',
      variant: '125 / 160 (eSP+ 4 van)',
      yearRange: '2020–2026',
      verifiedOilIntervalKm: 2000,
      verifiedPeriodicServiceKm: 4000,
      sourceReference: 'Hướng dẫn sử dụng Honda Việt Nam (eSP+)',
    ),
    VerifiedVehicleModelSpec(
      specId: 'honda_sh_125i_160i_2020_2026',
      brand: 'Honda',
      modelName: 'SH',
      variant: '125i / 160i ABS/CBS',
      yearRange: '2020–2026',
      verifiedOilIntervalKm: 2000,
      verifiedPeriodicServiceKm: 4000,
      sourceReference: 'Hướng dẫn sử dụng Honda SH Việt Nam',
    ),
    VerifiedVehicleModelSpec(
      specId: 'yamaha_grande_hybrid_2019_2026',
      brand: 'Yamaha',
      modelName: 'Grande',
      variant: 'Blue Core Hybrid 125',
      yearRange: '2019–2026',
      verifiedOilIntervalKm: 2000,
      verifiedPeriodicServiceKm: 4000,
      sourceReference: 'Sổ bảo dưỡng Yamaha Motor Việt Nam',
    ),
    VerifiedVehicleModelSpec(
      specId: 'yamaha_exciter_155_vva_2021_2026',
      brand: 'Yamaha',
      modelName: 'Exciter 155',
      variant: 'VVA Tiêu chuẩn / GP',
      yearRange: '2021–2026',
      verifiedOilIntervalKm: 2000,
      verifiedPeriodicServiceKm: 3000,
      sourceReference: 'Tài liệu kỹ thuật Yamaha Exciter 155 VVA',
    ),
    VerifiedVehicleModelSpec(
      specId: 'vinfast_evo200_lfp_2022_2026',
      brand: 'VinFast',
      modelName: 'Evo200',
      variant: 'Tiêu chuẩn / Lite (Pin LFP)',
      yearRange: '2022–2026',
      isElectric: true,
      verifiedOilIntervalKm: null,
      verifiedPeriodicServiceKm: 5000,
      sourceReference: 'Lịch bảo dưỡng xe máy điện VinFast LFP',
    ),
    VerifiedVehicleModelSpec(
      specId: 'toyota_vios_1_5_2019_2026',
      brand: 'Toyota',
      modelName: 'Vios',
      variant: '1.5E / 1.5G CVT',
      yearRange: '2019–2026',
      requiresPeriodicInspection: true,
      verifiedOilIntervalKm: 5000,
      verifiedPeriodicServiceKm: 10000,
      sourceReference: 'Lịch bảo dưỡng định kỳ Toyota Việt Nam',
    ),
    VerifiedVehicleModelSpec(
      specId: 'vinfast_vf5_plus_2023_2026',
      brand: 'VinFast',
      modelName: 'VF 5 Plus',
      variant: 'Thuê pin / Kèm pin LFP',
      yearRange: '2023–2026',
      isElectric: true,
      requiresPeriodicInspection: true,
      verifiedOilIntervalKm: null,
      verifiedPeriodicServiceKm: 12000,
      sourceReference: 'Sổ tay chủ xe ô tô điện VinFast VF 5',
    ),
  ];

  /// Returns a verified OEM spec ONLY when brand & model match an authoritative entry;
  /// returns `null` for unknown models (never guesses intervals!).
  static VerifiedVehicleModelSpec? lookupVerifiedSpec({
    required String brand,
    required String modelName,
  }) {
    final b = brand.trim().toLowerCase();
    final m = modelName.trim().toLowerCase();
    if (b.isEmpty || m.isEmpty) return null;
    for (final spec in verifiedCatalog) {
      if (spec.brand.toLowerCase() == b &&
          (spec.modelName.toLowerCase() == m ||
              m.contains(spec.modelName.toLowerCase()))) {
        return spec;
      }
    }
    return null;
  }

  static VehicleOwnershipAnalytics computeAnalytics({
    required String vehicleId,
    required List<FuelOrChargeLog> fuelLogs,
    required int maintenanceAndRepairMinor,
    required int insuranceAndInspectionMinor,
    int? nextOilDueOdoKm,
    DateTime? referenceNow,
  }) {
    final sorted = List<FuelOrChargeLog>.from(fuelLogs)
      ..sort((a, b) => a.odometerKm.compareTo(b.odometerKm));

    final fuelCost = sorted.fold<int>(0, (s, e) => s + e.costMinor);
    final tco =
        fuelCost + maintenanceAndRepairMinor + insuranceAndInspectionMinor;

    if (sorted.length < 2) {
      return VehicleOwnershipAnalytics(
        vehicleId: vehicleId,
        totalFuelCostMinor: fuelCost,
        totalMaintenanceAndRepairMinor: maintenanceAndRepairMinor,
        totalInsuranceAndInspectionMinor: insuranceAndInspectionMinor,
        totalCostOfOwnershipMinor: tco,
        trackedDistanceKm: 0,
      );
    }

    final first = sorted.first;
    final last = sorted.last;
    final distanceKm = math.max(0, last.odometerKm - first.odometerKm);
    int? costPerKm;
    double? consumption100Km;
    double? dailyKm;
    DateTime? nextOilDate;

    if (distanceKm > 0) {
      // Exclude the initial baseline fill's fuel volume & cost when computing per-km interval efficiency
      final subsequentFuelVolume = sorted
          .skip(1)
          .fold<double>(0.0, (s, e) => s + e.litersOrKwh);
      final subsequentFuelCost = sorted
          .skip(1)
          .fold<int>(0, (s, e) => s + e.costMinor);
      final intervalTco =
          subsequentFuelCost +
          maintenanceAndRepairMinor +
          insuranceAndInspectionMinor;
      costPerKm = (intervalTco / distanceKm).round();
      if (subsequentFuelVolume > 0) {
        consumption100Km = double.parse(
          ((subsequentFuelVolume * 100.0) / distanceKm).toStringAsFixed(2),
        );
      }

      final elapsedHours = last.loggedAt.difference(first.loggedAt).inHours;
      if (elapsedHours >= 24) {
        dailyKm = distanceKm / (elapsedHours / 24.0);
        if (nextOilDueOdoKm != null && dailyKm > 0.2) {
          final remKm = nextOilDueOdoKm - last.odometerKm;
          final ref = referenceNow ?? last.loggedAt;
          if (remKm <= 0) {
            nextOilDate = ref;
          } else {
            nextOilDate = ref.add(Duration(days: (remKm / dailyKm).ceil()));
          }
        }
      }
    }

    return VehicleOwnershipAnalytics(
      vehicleId: vehicleId,
      totalFuelCostMinor: fuelCost,
      totalMaintenanceAndRepairMinor: maintenanceAndRepairMinor,
      totalInsuranceAndInspectionMinor: insuranceAndInspectionMinor,
      totalCostOfOwnershipMinor: tco,
      trackedDistanceKm: distanceKm,
      costPerKmMinor: costPerKm,
      consumptionPer100Km: consumption100Km,
      averageDailyKm: dailyKm != null
          ? double.parse(dailyKm.toStringAsFixed(1))
          : null,
      predictedNextOilDueDate: nextOilDate,
    );
  }
}
