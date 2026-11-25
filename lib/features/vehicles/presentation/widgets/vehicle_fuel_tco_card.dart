import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/services/native_secure_vault_bridge.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../domain/entities/vehicle_entities.dart';
import '../../domain/services/vehicle_intelligence_engine.dart';

/// Fuel / EV Charge Efficiency (`L/100km` or `kWh/100km`), Cost-per-Km (`₫/km` TCO),
/// and Verified OEM Source Reference Card (Section 25).
class VehicleFuelAndTcoCard extends StatefulWidget {
  final VehicleEntity vehicle;
  final int maintenanceCostMinor;

  const VehicleFuelAndTcoCard({
    super.key,
    required this.vehicle,
    required this.maintenanceCostMinor,
  });

  @override
  State<VehicleFuelAndTcoCard> createState() => _VehicleFuelAndTcoCardState();
}

class _VehicleFuelAndTcoCardState extends State<VehicleFuelAndTcoCard> {
  List<FuelOrChargeLog> _logs = const <FuelOrChargeLog>[];

  String get _vaultKey => 'fuel_logs_v1_${widget.vehicle.id}';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void didUpdateWidget(covariant VehicleFuelAndTcoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicle.id != widget.vehicle.id) {
      _loadLogs();
    }
  }

  Future<void> _loadLogs() async {
    final raw = await NativeSecureVaultBridge.instance.readSecret(_vaultKey);
    if (!mounted) return;
    if (raw == null || raw.isEmpty) {
      setState(() => _logs = const <FuelOrChargeLog>[]);
      return;
    }
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<dynamic, dynamic>>()
          .map((m) {
            final map = Map<String, dynamic>.from(m);
            return FuelOrChargeLog(
              id: (map['id'] ?? '').toString(),
              vehicleId: widget.vehicle.id,
              odometerKm: (map['odometerKm'] as num?)?.toInt() ?? 0,
              litersOrKwh: (map['litersOrKwh'] as num?)?.toDouble() ?? 0.0,
              costMinor: (map['costMinor'] as num?)?.toInt() ?? 0,
              loggedAt:
                  DateTime.tryParse((map['loggedAt'] ?? '').toString()) ??
                  DateTime.now(),
            );
          })
          .toList();
      setState(() => _logs = list);
    } catch (_) {
      setState(() => _logs = const <FuelOrChargeLog>[]);
    }
  }

  Future<void> _saveLogs(List<FuelOrChargeLog> next) async {
    setState(() => _logs = next);
    final encoded = jsonEncode(
      next
          .map(
            (e) => <String, dynamic>{
              'id': e.id,
              'odometerKm': e.odometerKm,
              'litersOrKwh': e.litersOrKwh,
              'costMinor': e.costMinor,
              'loggedAt': e.loggedAt.toUtc().toIso8601String(),
            },
          )
          .toList(),
    );
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _vaultKey,
      value: encoded,
    );
  }

  Future<void> _showAddFuelDialog(BuildContext context, bool isElectric) async {
    final odoCtrl = TextEditingController(
      text: widget.vehicle.currentOdometerKm.toString(),
    );
    final volCtrl = TextEditingController(text: isElectric ? '12.5' : '3.8');
    final costCtrl = TextEditingController(
      text: isElectric ? '45000' : '90000',
    );

    final added = await showDialog<FuelOrChargeLog>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isElectric ? 'Ghi nhận Sạc điện' : 'Ghi nhận Đổ xăng'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('fuel_log_odo_input'),
                controller: odoCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số ODO hiện tại (km)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('fuel_log_volume_input'),
                controller: volCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: isElectric
                      ? 'Điện năng sạc (kWh)'
                      : 'Số lít xăng (L)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('fuel_log_cost_input'),
                controller: costCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Chi phí (VND)',
                  suffixText: 'VND',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('fuel_log_submit_btn'),
            onPressed: () {
              final odo =
                  int.tryParse(odoCtrl.text.replaceAll('.', '').trim()) ?? 0;
              final vol =
                  double.tryParse(volCtrl.text.replaceAll(',', '.').trim()) ??
                  0.0;
              final cost = VndAmount.tryParseInput(costCtrl.text) ?? 0;
              if (odo <= 0 || vol <= 0 || cost <= 0) return;
              Navigator.of(ctx).pop(
                FuelOrChargeLog(
                  id: 'fuel_${DateTime.now().millisecondsSinceEpoch}',
                  vehicleId: widget.vehicle.id,
                  odometerKm: odo,
                  litersOrKwh: vol,
                  costMinor: cost,
                  loggedAt: DateTime.now(),
                ),
              );
            },
            child: const Text('Lưu nhật ký'),
          ),
        ],
      ),
    );

    if (added != null && context.mounted) {
      await _saveLogs(<FuelOrChargeLog>[..._logs, added]);
      if (context.mounted) {
        LifeOsTopToast.show(
          context,
          'Đã lưu nhật ký nhiên liệu ODO ${added.odometerKm} km.',
          kind: LifeOsToastKind.success,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final profile = widget.vehicle.maintenanceProfile;
    final isElectric = profile.profileKey.contains('ev');
    final verifiedSpec = VehicleIntelligenceEngine.lookupVerifiedSpec(
      brand: profile.brandName,
      modelName: widget.vehicle.name,
    );
    final analytics = VehicleIntelligenceEngine.computeAnalytics(
      vehicleId: widget.vehicle.id,
      fuelLogs: _logs,
      maintenanceAndRepairMinor: widget.maintenanceCostMinor,
      insuranceAndInspectionMinor: 0,
      nextOilDueOdoKm: isElectric ? null : widget.vehicle.nextDueKm,
      referenceNow: DateTime.now(),
    );
    final dateFmt = DateFormat('dd/MM/yyyy');

    return LifeOsSoftCard(
      key: const Key('vehicle_fuel_and_tco_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LifeOsIconSquircle(
                    icon: isElectric
                        ? Icons.ev_station_rounded
                        : Icons.local_gas_station_rounded,
                    tone: LifeOsAccentTone.emerald,
                    size: 32,
                    iconSize: 17,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      isElectric
                          ? 'Hiệu suất Sạc điện & Tổng chi phí (TCO)'
                          : 'Tiêu hao Xăng & Chi phí Vận hành / km',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14.2,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              FilledButton.tonalIcon(
                key: const Key('vehicle_add_fuel_log_btn'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _showAddFuelDialog(context, isElectric),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(isElectric ? 'Ghi sạc điện' : 'Ghi đổ xăng'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isElectric ? 'Mức tiêu thụ' : 'Tiêu hao nhiên liệu',
                        style: TextStyle(
                          fontSize: 11.4,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          analytics.consumptionPer100Km != null
                              ? '${analytics.consumptionPer100Km!.toStringAsFixed(2)} ${isElectric ? "kWh" : "L"}/100km'
                              : 'Cần >= 2 lần ghi',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: c.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(width: 14, color: c.separator),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chi phí thực tế / km',
                        style: TextStyle(
                          fontSize: 11.4,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          analytics.costPerKmMinor != null
                              ? '${VndAmount.format(analytics.costPerKmMinor!)}/km'
                              : VndAmount.format(
                                  analytics.totalCostOfOwnershipMinor,
                                ),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (analytics.predictedNextOilDueDate != null) ...[
            const SizedBox(height: 8),
            Text(
              'Dự kiến chạm mốc thay nhớt kế tiếp vào khoảng ${dateFmt.format(analytics.predictedNextOilDueDate!)} (trung bình ${analytics.averageDailyKm ?? 0} km/ngày).',
              softWrap: true,
              style: TextStyle(
                fontSize: 11.8,
                color: c.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            verifiedSpec != null
                ? 'Nguồn chuẩn hãng đã xác minh: ${verifiedSpec.sourceReference}'
                : 'Dòng xe tùy chỉnh — đang dùng chu kỳ bảo dưỡng bạn tự cấu hình.',
            softWrap: true,
            style: TextStyle(fontSize: 11.2, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}
