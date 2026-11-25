import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../domain/entities/vehicle_entities.dart';
import '../bloc/vehicle_bloc.dart';
import '../widgets/vehicle_bills_and_spec_sheet.dart';
import '../widgets/vehicle_fuel_tco_card.dart';

/// Motorcycle-first Vehicle Maintenance, OEM Technical Spec Sheet & Recurring Bills screen
/// crafted in Apple Liquid Glass for Vietnamese riders and households.
class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return BlocListener<VehicleBloc, VehicleState>(
      listenWhen: (p, c) => p.failure != c.failure || p.message != c.message,
      listener: (context, state) {
        if (state.failure != null) {
          LifeOsTopToast.show(
            context,
            state.failure!.message,
            kind: LifeOsToastKind.error,
          );
        } else if (state.message != null) {
          LifeOsTopToast.show(
            context,
            state.message!,
            kind: LifeOsToastKind.success,
          );
        }
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              child: Column(
                children: [
                  LifeOsTopBrandHeader(
                    title: 'Xe cộ & Hóa đơn',
                    showBackButton: true,
                    extraBrandActions: [
                      LifeOsHeaderCircleButton(
                        icon: Icons.menu_book_rounded,
                        tooltip: 'Cẩm nang thông số các dòng xe',
                        onTap: () => _showSpecEncyclopediaSheet(context),
                      ),
                      LifeOsHeaderCircleButton(
                        icon: Icons.receipt_long_outlined,
                        tooltip: 'Thêm hóa đơn định kỳ',
                        onTap: () => _showAddBillSheet(
                          context,
                          user.id,
                          user.activeFamilyId,
                        ),
                      ),
                    ],
                    trailingAction: FilledButton.icon(
                      key: const Key('assets_add_vehicle_btn'),
                      onPressed: () => _showAddVehicleSheet(
                        context,
                        user.id,
                        user.activeFamilyId,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Thêm xe'),
                    ),
                  ),
                  const ProPillTabContainer(
                    tabBar: TabBar(
                      tabs: [
                        Tab(text: 'Xe máy & Bảo dưỡng'),
                        Tab(text: 'Hóa đơn định kỳ'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: BlocBuilder<VehicleBloc, VehicleState>(
                      builder: (context, state) {
                        return TabBarView(
                          children: [
                            _UnifiedVehiclesTab(
                              userId: user.id,
                              familyId: user.activeFamilyId,
                              vehicles: state.vehicles,
                              maintenanceHistoryByVehicleId:
                                  state.maintenanceHistoryByVehicleId,
                              defaultWalletId: wallets.isNotEmpty
                                  ? wallets.first.id
                                  : null,
                              onAddVehicle: ({String? presetProfileKey}) =>
                                  _showAddVehicleSheet(
                                    context,
                                    user.id,
                                    user.activeFamilyId,
                                    presetProfileKey: presetProfileKey,
                                  ),
                            ),
                            UnifiedRecurringBillsTab(
                              userId: user.id,
                              bills: state.bills,
                              defaultWalletId: wallets.isNotEmpty
                                  ? wallets.first.id
                                  : null,
                              onAddBill: () => _showAddBillSheet(
                                context,
                                user.id,
                                user.activeFamilyId,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _showAddVehicleSheet(
    BuildContext context,
    String userId,
    String? familyId, {
    String? presetProfileKey,
  }) async {
    final initialProfile = presetProfileKey != null
        ? MotorcycleSpecCatalog.byKey(presetProfileKey)
        : MotorcycleSpecCatalog.defaultMotorcycleProfile;
    var selectedCategory = initialProfile.category;
    var selectedProfile = initialProfile;
    final nameCtrl = TextEditingController(
      text: presetProfileKey != null
          ? initialProfile.modelLineTitle.split('(').first.trim()
          : '',
    );
    final plateCtrl = TextEditingController();
    final odoCtrl = TextEditingController();
    DateTime? insuranceExpiry;
    DateTime? inspectionExpiry;
    var shared = false;
    final bloc = context.read<VehicleBloc>();
    final dateFmt = DateFormat('dd/MM/yyyy');
    final numFmt = NumberFormat('#,###', 'vi_VN');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final c = TammySemanticColors.of(ctx);
          final matchingProfiles = MotorcycleSpecCatalog.allProfiles
              .where((p) => p.category == selectedCategory)
              .toList(growable: false);

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: LiquidGlassSheetFrame(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        BananaGlassIcon(
                          assetPath: selectedCategory.isMotorcycle
                              ? AppAssets.icCatScooter
                              : AppAssets.icCatVehicle,
                          fallbackIcon: selectedCategory.isMotorcycle
                              ? Icons.two_wheeler_rounded
                              : Icons.directions_car_filled_outlined,
                          size: 42,
                          borderRadius: 13,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Thêm Xe & Cấu hình Dòng máy',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '1. Loại phương tiện',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: VehicleCategory.values.map((cat) {
                        final picked = cat == selectedCategory;
                        return ChoiceChip(
                          selected: picked,
                          label: Text(cat.displayLabel),
                          onSelected: (_) {
                            final firstForCat = MotorcycleSpecCatalog
                                .allProfiles
                                .firstWhere((p) => p.category == cat);
                            setSheetState(() {
                              selectedCategory = cat;
                              selectedProfile = firstForCat;
                              if (!cat.requiresPeriodicInspection) {
                                inspectionExpiry = null;
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '2. Dòng máy chuẩn hãng',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: matchingProfiles.map((p) {
                        final picked =
                            p.profileKey == selectedProfile.profileKey;
                        return ChoiceChip(
                          key: Key('select_profile_${p.profileKey}'),
                          selected: picked,
                          label: Text(p.modelLineTitle),
                          onSelected: (_) {
                            setSheetState(() {
                              selectedProfile = p;
                              if (nameCtrl.text.trim().isEmpty) {
                                nameCtrl.text = p.modelLineTitle
                                    .split('(')
                                    .first
                                    .split('/')
                                    .first
                                    .trim();
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _OemCompactPreviewBanner(
                      profile: selectedProfile,
                      numFmt: numFmt,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('vehicle_name_input'),
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Tên gợi nhớ của xe',
                        hintText: selectedCategory.isMotorcycle
                            ? 'VD: Honda Air Blade 160 / Vision trắng'
                            : 'VD: Mazda CX-5 Gia đình',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('vehicle_plate_input'),
                            controller: plateCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: 'Biển kiểm soát',
                              hintText: selectedCategory.platePlaceholder,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: const Key('vehicle_odo_input'),
                            controller: odoCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Số ODO hiện tại (km)',
                              hintText: 'VD: 8500',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate:
                                  insuranceExpiry ??
                                  DateTime.now().add(const Duration(days: 365)),
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setSheetState(() => insuranceExpiry = picked);
                            }
                          },
                          icon: const Icon(
                            Icons.verified_user_outlined,
                            size: 17,
                          ),
                          label: Text(
                            insuranceExpiry != null
                                ? 'BH TNDS: ${dateFmt.format(insuranceExpiry!)}'
                                : 'Hạn BH TNDS (~${VndAmount.format(selectedCategory.mandatoryInsuranceReferenceMinor)}/năm)',
                          ),
                        ),
                        if (selectedCategory.requiresPeriodicInspection)
                          OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate:
                                    inspectionExpiry ??
                                    DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setSheetState(() => inspectionExpiry = picked);
                              }
                            },
                            icon: const Icon(
                              Icons.fact_check_outlined,
                              size: 17,
                            ),
                            label: Text(
                              inspectionExpiry != null
                                  ? 'Đăng kiểm: ${dateFmt.format(inspectionExpiry!)}'
                                  : 'Chọn hạn Đăng kiểm ô tô',
                            ),
                          ),
                      ],
                    ),
                    if (familyId != null) ...[
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Chia sẻ lịch bảo dưỡng với gia đình',
                        ),
                        subtitle: const Text(
                          'Tự động che bớt biển số đối với thành viên khác',
                        ),
                        value: shared,
                        onChanged: (v) => setSheetState(() => shared = v),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Đóng'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            key: const Key('vehicle_submit_save_btn'),
                            onPressed: () {
                              final fallbackName = selectedProfile
                                  .modelLineTitle
                                  .split('(')
                                  .first
                                  .split('/')
                                  .first
                                  .trim();
                              final effectiveName = nameCtrl.text.trim().isEmpty
                                  ? fallbackName
                                  : nameCtrl.text.trim();
                              bloc.add(
                                VehicleCreated(
                                  userId: userId,
                                  familyId: familyId,
                                  isFamilyShared: shared,
                                  name: effectiveName,
                                  plateNumber: plateCtrl.text,
                                  currentOdometerKm:
                                      int.tryParse(
                                        odoCtrl.text.replaceAll('.', ''),
                                      ) ??
                                      0,
                                  serviceIntervalKm:
                                      selectedProfile.recommendedOilIntervalKm,
                                  serviceIntervalDays:
                                      selectedProfile.recommendedIntervalDays,
                                  category: selectedCategory,
                                  modelProfileKey: selectedProfile.profileKey,
                                  insuranceExpiryDate: insuranceExpiry,
                                  inspectionExpiryDate: inspectionExpiry,
                                ),
                              );
                              Navigator.of(ctx).pop();
                            },
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Lưu xe & Áp dụng chuẩn hãng'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<void> _showSpecEncyclopediaSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.86,
          minChildSize: 0.55,
          maxChildSize: 0.94,
          expand: false,
          builder: (ctx, scrollCtrl) => LiquidGlassSheetFrame(
            child: VehicleSpecEncyclopediaSheetBody(
              scrollController: scrollCtrl,
            ),
          ),
        );
      },
    );
  }

  static Future<void> _showAddBillSheet(
    BuildContext context,
    String userId,
    String? familyId,
  ) async {
    final titleCtrl = TextEditingController();
    final providerCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    var nextDueDate = DateTime.now().add(const Duration(days: 5));
    final dateFmt = DateFormat('dd/MM/yyyy');
    final bloc = context.read<VehicleBloc>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final c = TammySemanticColors.of(ctx);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: LiquidGlassSheetFrame(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Thêm Hóa đơn Định kỳ',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên hóa đơn',
                        hintText: 'VD: Tiền điện EVN / Gửi xe tháng / Internet',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: providerCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nhà cung cấp',
                        hintText: 'VD: EVN / FPT / Ban quản lý',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Số tiền dự kiến (VND)',
                        hintText: 'VD: 350000',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: nextDueDate,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 30),
                          ),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setSheetState(() => nextDueDate = picked);
                        }
                      },
                      icon: const Icon(Icons.event_available_rounded, size: 18),
                      label: Text(
                        'Kỳ hạn thanh toán: ${dateFmt.format(nextDueDate)}',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Hủy'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: () {
                              final amt =
                                  VndAmount.tryParseInput(amountCtrl.text) ?? 0;
                              bloc.add(
                                RecurringBillCreated(
                                  userId: userId,
                                  familyId: familyId,
                                  title: titleCtrl.text,
                                  providerName: providerCtrl.text,
                                  estimatedAmountMinor: amt,
                                  nextDueDate: nextDueDate,
                                ),
                              );
                              Navigator.of(ctx).pop();
                            },
                            child: const Text('Lưu hóa đơn'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OemCompactPreviewBanner extends StatelessWidget {
  final EngineMaintenanceProfile profile;
  final NumberFormat numFmt;

  const _OemCompactPreviewBanner({required this.profile, required this.numFmt});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return LifeOsMintHeroCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Định mức chuẩn: ${profile.modelLineTitle}',
            softWrap: true,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: c.primary,
            ),
          ),
          const SizedBox(height: 6),
          _SpecKeyValueLine(label: 'Chuẩn nhớt', value: profile.oilGradeSpec),
          _SpecKeyValueLine(
            label: 'Nhớt máy',
            value: profile.engineOilCapacity,
          ),
          if (profile.gearOilCapacity != null)
            _SpecKeyValueLine(
              label: 'Nhớt láp',
              value: profile.gearOilCapacity!,
            ),
          _SpecKeyValueLine(label: 'Làm mát', value: profile.coolingSystem),
          _SpecKeyValueLine(
            label: 'Chu kỳ nhắc',
            value:
                'Mỗi ${numFmt.format(profile.recommendedOilIntervalKm)} km · ${profile.components.length} hạng mục theo dõi riêng',
          ),
        ],
      ),
    );
  }
}

class _SpecKeyValueLine extends StatelessWidget {
  final String label;
  final String value;

  const _SpecKeyValueLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 12.4,
            height: 1.35,
            color: c.textSecondary,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _UnifiedVehiclesTab extends StatefulWidget {
  final String userId;
  final String? familyId;
  final List<VehicleEntity> vehicles;
  final Map<String, List<MaintenanceRecordEntity>>
  maintenanceHistoryByVehicleId;
  final String? defaultWalletId;
  final void Function({String? presetProfileKey}) onAddVehicle;

  const _UnifiedVehiclesTab({
    required this.userId,
    this.familyId,
    required this.vehicles,
    required this.maintenanceHistoryByVehicleId,
    this.defaultWalletId,
    required this.onAddVehicle,
  });

  @override
  State<_UnifiedVehiclesTab> createState() => _UnifiedVehiclesTabState();
}

class _UnifiedVehiclesTabState extends State<_UnifiedVehiclesTab> {
  int _selectedIdx = 0;
  String? _watchedHistoryVehicleId;

  void _ensureWatchingHistory(VehicleEntity? active) {
    if (active == null) return;
    if (_watchedHistoryVehicleId == active.id) return;
    _watchedHistoryVehicleId = active.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<VehicleBloc>().add(VehicleMaintenanceHistoryWatched(active));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final now = DateTime.now();
    final numFmt = NumberFormat('#,###', 'vi_VN');
    final dateFmt = DateFormat('dd/MM/yyyy');

    final activeVehicle = widget.vehicles.isNotEmpty
        ? widget.vehicles[_selectedIdx.clamp(0, widget.vehicles.length - 1)]
        : null;
    _ensureWatchingHistory(activeVehicle);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          key: const Key('vehicles_maintenance_list_view'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            6,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            if (widget.vehicles.length > 1) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(widget.vehicles.length, (i) {
                    final v = widget.vehicles[i];
                    final picked = i == _selectedIdx;
                    final canDelete =
                        !v.isFamilyShared ||
                        v.ownerId.isEmpty ||
                        v.ownerId == widget.userId;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 10),
                      child: InputChip(
                        key: Key('vehicle_chip_${v.id}'),
                        selected: picked,
                        avatar: Icon(
                          v.isMotorcycle
                              ? Icons.two_wheeler_rounded
                              : Icons.directions_car_filled_outlined,
                          size: 16,
                        ),
                        label: Text(v.name),
                        onSelected: (_) {
                          setState(() {
                            _selectedIdx = i;
                            _watchedHistoryVehicleId = null;
                          });
                        },
                        deleteIcon: canDelete
                            ? const Icon(Icons.close_rounded, size: 16)
                            : null,
                        deleteButtonTooltipMessage: 'Xóa xe này',
                        onDeleted: canDelete
                            ? () => _confirmDeleteVehicle(context, v)
                            : null,
                      ),
                    );
                  }),
                ),
              ),
            ],

            if (activeVehicle == null)
              LifeOsMintHeroCard(
                child: Column(
                  children: [
                    const BananaGlassIcon(
                      assetPath: AppAssets.icCatScooter,
                      fallbackIcon: Icons.two_wheeler_rounded,
                      size: 64,
                      borderRadius: 18,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Theo dõi Bảo dưỡng Xe máy Chuẩn hãng',
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Chọn dòng xe để nạp định mức nhớt & chu kỳ bảo dưỡng.',
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        ActionChip(
                          avatar: const Icon(
                            Icons.two_wheeler_rounded,
                            size: 16,
                          ),
                          label: const Text('Honda Vision 110'),
                          onPressed: () => widget.onAddVehicle(
                            presetProfileKey: 'honda_esp_vision_110',
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.two_wheeler_rounded,
                            size: 16,
                          ),
                          label: const Text('Air Blade / Lead / SH'),
                          onPressed: () => widget.onAddVehicle(
                            presetProfileKey: 'honda_esp_plus_125_160',
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.two_wheeler_rounded,
                            size: 16,
                          ),
                          label: const Text('Wave / Future'),
                          onPressed: () => widget.onAddVehicle(
                            presetProfileKey: 'honda_wave_future',
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.two_wheeler_rounded,
                            size: 16,
                          ),
                          label: const Text('Grande / Exciter / Vespa'),
                          onPressed: () => widget.onAddVehicle(
                            presetProfileKey: 'yamaha_grande_janus',
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.electric_moped_rounded,
                            size: 16,
                          ),
                          label: const Text('Xe máy điện VinFast'),
                          onPressed: () => widget.onAddVehicle(
                            presetProfileKey: 'vinfast_ev_scooter',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => widget.onAddVehicle(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Thêm xe máy hoặc ô tô đầu tiên'),
                    ),
                  ],
                ),
              )
            else
              Builder(
                builder: (context) {
                  final profile = activeVehicle.maintenanceProfile;
                  final checklist = activeVehicle.evaluateComponentChecklist();
                  final baseDue = activeVehicle.dueStateAt(now);
                  final worstChecklistDue =
                      checklist.any(
                        (s) => s.dueState == VehicleDueState.overdue,
                      )
                      ? VehicleDueState.overdue
                      : (checklist.any(
                              (s) => s.dueState == VehicleDueState.dueSoon,
                            )
                            ? VehicleDueState.dueSoon
                            : VehicleDueState.healthy);
                  final overallDue =
                      (baseDue == VehicleDueState.overdue ||
                          worstChecklistDue == VehicleDueState.overdue)
                      ? VehicleDueState.overdue
                      : ((baseDue == VehicleDueState.dueSoon ||
                                worstChecklistDue == VehicleDueState.dueSoon)
                            ? VehicleDueState.dueSoon
                            : VehicleDueState.healthy);

                  final remDays = activeVehicle.remainingDaysFrom(now);
                  final insuranceDate = activeVehicle.insuranceExpiryDate;
                  final insuranceRemDays = insuranceDate
                      ?.difference(now)
                      .inDays;
                  final history =
                      widget.maintenanceHistoryByVehicleId[activeVehicle.id] ??
                      const <MaintenanceRecordEntity>[];
                  final totalMaintCostMinor = history.fold<int>(
                    0,
                    (sum, r) => sum + r.costMinor,
                  );

                  final (pillTone, pillLabel, pillIcon) = switch (overallDue) {
                    VehicleDueState.overdue => (
                      LifeOsAccentTone.coral,
                      'Cần bảo dưỡng',
                      Icons.error_outline_rounded,
                    ),
                    VehicleDueState.dueSoon => (
                      LifeOsAccentTone.amber,
                      'Sắp đến hạn',
                      Icons.schedule_rounded,
                    ),
                    VehicleDueState.healthy => (
                      LifeOsAccentTone.emerald,
                      'Vận hành tốt',
                      Icons.check_circle_rounded,
                    ),
                  };

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Hero Vehicle Status Card
                      LifeOsSoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BananaGlassIcon(
                                  assetPath: activeVehicle.isMotorcycle
                                      ? AppAssets.icCatScooter
                                      : AppAssets.icCatVehicle,
                                  fallbackIcon: activeVehicle.isMotorcycle
                                      ? Icons.two_wheeler_rounded
                                      : Icons.directions_car_filled_outlined,
                                  size: 62,
                                  borderRadius: 18,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              activeVehicle
                                                  .displayPlateForViewer(
                                                    widget.userId,
                                                  ),
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.3,
                                                color: c.textPrimary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ),
                                          LifeOsStatusPill(
                                            icon: pillIcon,
                                            label: pillLabel,
                                            tone: pillTone,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        activeVehicle.name,
                                        softWrap: true,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${profile.category.displayLabel} · ${profile.brandName}',
                                        softWrap: true,
                                        style: TextStyle(
                                          fontSize: 12.2,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!activeVehicle.isFamilyShared ||
                                    activeVehicle.ownerId.isEmpty ||
                                    activeVehicle.ownerId == widget.userId)
                                  IconButton(
                                    key: const Key('vehicle_delete_btn'),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Xóa xe này',
                                    onPressed: () => _confirmDeleteVehicle(
                                      context,
                                      activeVehicle,
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 20,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                              ],
                            ),
                            const Divider(height: 24),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.oil_barrel_outlined,
                                          size: 19,
                                          color: c.primary,
                                        ),
                                        const SizedBox(height: 6),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            activeVehicle.isMotorcycle
                                                ? 'Thay nhớt kế tiếp'
                                                : 'Bảo dưỡng kế tiếp',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            '${numFmt.format(activeVehicle.nextDueKm)} km',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: c.textPrimary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            activeVehicle.remainingKm >= 0
                                                ? 'Còn ${numFmt.format(activeVehicle.remainingKm)} km'
                                                : 'Quá hạn ${numFmt.format(-activeVehicle.remainingKm)} km',
                                            style: TextStyle(
                                              fontSize: 11.4,
                                              color:
                                                  remDays < 0 ||
                                                      activeVehicle
                                                              .remainingKm <
                                                          0
                                                  ? const Color(0xFFC92A2A)
                                                  : c.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  VerticalDivider(
                                    width: 12,
                                    color: c.separator,
                                  ),
                                  Expanded(
                                    child: InkWell(
                                      key: const Key('vehicle_update_odo_tap'),
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => _showOdometerSheet(
                                        context,
                                        activeVehicle,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.speed_rounded,
                                            size: 19,
                                            color: c.primary,
                                          ),
                                          const SizedBox(height: 6),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Số ODO (chạm sửa)',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              '${numFmt.format(activeVehicle.currentOdometerKm)} km',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Text(
                                            'Chu kỳ ${numFmt.format(activeVehicle.serviceIntervalKm)} km',
                                            softWrap: true,
                                            style: TextStyle(
                                              fontSize: 11.4,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  VerticalDivider(
                                    width: 12,
                                    color: c.separator,
                                  ),
                                  Expanded(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => _showEditSpecSheet(
                                        context,
                                        activeVehicle,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.verified_user_outlined,
                                            size: 19,
                                            color: c.primary,
                                          ),
                                          const SizedBox(height: 6),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Bảo hiểm TNDS',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              insuranceDate != null
                                                  ? dateFmt.format(
                                                      insuranceDate,
                                                    )
                                                  : 'Chưa đặt hạn',
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                          ),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              insuranceRemDays != null
                                                  ? (insuranceRemDays >= 0
                                                        ? 'Còn $insuranceRemDays ngày'
                                                        : 'Quá hạn ${-insuranceRemDays} ngày')
                                                  : 'Chạm cập nhật',
                                              style: TextStyle(
                                                fontSize: 11.4,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            LifeOsDetailsDiscloseSection(
                              toggleKey: const Key(
                                'vehicle_summary_details_toggle',
                              ),
                              label: 'Chi tiết tổng hợp',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _SpecKeyValueLine(
                                    label: 'ODO bảo dưỡng gần nhất',
                                    value:
                                        '${numFmt.format(activeVehicle.lastServiceOdometerKm)} km',
                                  ),
                                  _SpecKeyValueLine(
                                    label: 'Chu kỳ thời gian',
                                    value:
                                        '${activeVehicle.serviceIntervalDays} ngày (${remDays >= 0 ? "còn $remDays ngày" : "quá hạn ${-remDays} ngày"})',
                                  ),
                                  _SpecKeyValueLine(
                                    label: 'Tổng chi phí đã ghi',
                                    value:
                                        '${VndAmount.format(totalMaintCostMinor)} (${history.length} lần)',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      VehicleFuelAndTcoCard(
                        vehicle: activeVehicle,
                        maintenanceCostMinor: totalMaintCostMinor,
                      ),
                      const SizedBox(height: 12),

                      // 2. Manufacturer OEM Specification Card ("Thông số kỹ thuật & Định mức chuẩn hãng")
                      LifeOsMintHeroCard(
                        key: const Key('vehicle_oem_spec_card'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.tune_rounded,
                                      size: 20,
                                      color: c.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'Thông số chuẩn hãng',
                                        softWrap: true,
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                OutlinedButton.icon(
                                  key: const Key('vehicle_change_spec_btn'),
                                  onPressed: () => _showEditSpecSheet(
                                    context,
                                    activeVehicle,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(
                                    Icons.swap_horiz_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Đổi dòng máy'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              profile.modelLineTitle,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: c.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _SpecKeyValueLine(
                              label: 'Chuẩn dầu nhớt',
                              value: profile.oilGradeSpec,
                            ),
                            _SpecKeyValueLine(
                              label: 'Dung tích nhớt máy',
                              value: profile.engineOilCapacity,
                            ),
                            if (profile.gearOilCapacity != null)
                              _SpecKeyValueLine(
                                label: 'Dung tích nhớt láp (hộp số)',
                                value: profile.gearOilCapacity!,
                              ),
                            const SizedBox(height: 6),
                            LifeOsDetailsDiscloseSection(
                              toggleKey: const Key(
                                'vehicle_oem_details_toggle',
                              ),
                              label: 'Chi tiết kỹ thuật',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _SpecKeyValueLine(
                                    label: 'Động cơ',
                                    value: profile.engineTechSummary,
                                  ),
                                  _SpecKeyValueLine(
                                    label: 'Hệ thống làm mát',
                                    value: profile.coolingSystem,
                                  ),
                                  _SpecKeyValueLine(
                                    label: 'Chu kỳ khuyến nghị',
                                    value:
                                        '${numFmt.format(profile.recommendedOilIntervalKm)} km (${profile.recommendedIntervalDays} ngày)',
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    profile.firstBreakInNote,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 3. Dynamic Per-Component OEM Checklist Card
                      LifeOsSoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.build_circle_outlined,
                                  size: 20,
                                  color: c.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Định kỳ từng bộ phận (${checklist.length} hạng mục)',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            for (
                              var idx = 0;
                              idx < checklist.length;
                              idx++
                            ) ...[
                              if (idx > 0) const Divider(height: 22),
                              _OemComponentChecklistRow(
                                item: checklist[idx],
                                numFmt: numFmt,
                                onLogTap: () => _showMaintenanceSheet(
                                  context,
                                  activeVehicle,
                                  widget.defaultWalletId,
                                  presetSpec: checklist[idx].spec,
                                ),
                              ),
                            ],
                            if (profile
                                .category
                                .requiresPeriodicInspection) ...[
                              const Divider(height: 22),
                              _CarInspectionChecklistRow(
                                inspectionExpiryDate:
                                    activeVehicle.inspectionExpiryDate,
                                now: now,
                                dateFmt: dateFmt,
                                onTap: () =>
                                    _showEditSpecSheet(context, activeVehicle),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 4. Recent Maintenance Logbook ("Sổ lịch sử bảo dưỡng")
                      LifeOsSoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.history_edu_rounded,
                                  size: 20,
                                  color: c.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Nhật ký bảo dưỡng gần đây (${history.length})',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (history.isEmpty)
                              Text(
                                'Chưa có lịch sử bảo dưỡng.',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: c.textSecondary,
                                ),
                              )
                            else
                              ...history
                                  .take(6)
                                  .map(
                                    (rec) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.check_circle_outline_rounded,
                                            size: 18,
                                            color: c.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  rec.serviceTitle,
                                                  softWrap: true,
                                                  style: TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  '${dateFmt.format(rec.serviceDate)} · Tại ODO ${numFmt.format(rec.odometerKm)} km',
                                                  softWrap: true,
                                                  style: TextStyle(
                                                    fontSize: 11.8,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (rec.costMinor > 0)
                                            Text(
                                              VndAmount.format(rec.costMinor),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 5. Primary CTA
                      LifeOsPrimaryCtaButton(
                        icon: Icons.handyman_rounded,
                        label: activeVehicle.isMotorcycle
                            ? 'Ghi nhận thay nhớt / bảo dưỡng xe'
                            : 'Ghi nhận bảo dưỡng ô tô',
                        onPressed: () => _showMaintenanceSheet(
                          context,
                          activeVehicle,
                          widget.defaultWalletId,
                          presetSpec: checklist.firstOrNull?.spec,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 6. Bottom Quick Action Grid (adapted accurately for Motorcycle vs Car!)
                      Row(
                        children: [
                          Expanded(
                            child: LifeOsFeatureGridTile(
                              icon: Icons.speed_rounded,
                              label: 'Cập nhật ODO',
                              tone: LifeOsAccentTone.emerald,
                              onTap: () =>
                                  _showOdometerSheet(context, activeVehicle),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LifeOsFeatureGridTile(
                              icon: Icons.verified_user_outlined,
                              label: 'Bảo hiểm TNDS',
                              tone: LifeOsAccentTone.emerald,
                              onTap: () =>
                                  _showEditSpecSheet(context, activeVehicle),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LifeOsFeatureGridTile(
                              icon: profile.category.requiresPeriodicInspection
                                  ? Icons.fact_check_outlined
                                  : Icons.folder_open_rounded,
                              label: profile.category.requiresPeriodicInspection
                                  ? 'Đăng kiểm'
                                  : 'Giấy tờ xe',
                              tone: LifeOsAccentTone.emerald,
                              onTap: () => context.push('/family-documents'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOdometerSheet(
    BuildContext context,
    VehicleEntity vehicle,
  ) async {
    final ctrl = TextEditingController(
      text: (vehicle.currentOdometerKm + 250).toString(),
    );
    final bloc = context.read<VehicleBloc>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = TammySemanticColors.of(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: LiquidGlassSheetFrame(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cập nhật số ODO · ${vehicle.name}',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Số ODO hiện tại (km)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Hủy'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: () {
                            bloc.add(
                              VehicleOdometerLogged(
                                vehicle: vehicle,
                                newOdometerKm:
                                    int.tryParse(
                                      ctrl.text.replaceAll('.', ''),
                                    ) ??
                                    vehicle.currentOdometerKm,
                              ),
                            );
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('Lưu ODO mới'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditSpecSheet(
    BuildContext context,
    VehicleEntity vehicle,
  ) async {
    var selectedCategory = vehicle.maintenanceProfile.category;
    var selectedProfile = vehicle.maintenanceProfile;
    final nameCtrl = TextEditingController(text: vehicle.name);
    final plateCtrl = TextEditingController(text: vehicle.plateNumber);
    DateTime? insuranceExpiry = vehicle.insuranceExpiryDate;
    DateTime? inspectionExpiry = vehicle.inspectionExpiryDate;
    final bloc = context.read<VehicleBloc>();
    final dateFmt = DateFormat('dd/MM/yyyy');
    final numFmt = NumberFormat('#,###', 'vi_VN');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final c = TammySemanticColors.of(ctx);
          final profiles = MotorcycleSpecCatalog.allProfiles
              .where((p) => p.category == selectedCategory)
              .toList(growable: false);

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: LiquidGlassSheetFrame(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Hồ sơ & Dòng máy · ${vehicle.name}',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('edit_vehicle_name_input'),
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên phương tiện',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('edit_vehicle_plate_input'),
                      controller: plateCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Biển kiểm soát',
                        hintText: selectedCategory.platePlaceholder,
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: VehicleCategory.values.map((cat) {
                      return ChoiceChip(
                        selected: cat == selectedCategory,
                        label: Text(cat.displayLabel),
                        onSelected: (_) {
                          final first = MotorcycleSpecCatalog.allProfiles
                              .firstWhere((p) => p.category == cat);
                          setSheetState(() {
                            selectedCategory = cat;
                            selectedProfile = first;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: profiles.map((p) {
                      return ChoiceChip(
                        selected: p.profileKey == selectedProfile.profileKey,
                        label: Text(p.modelLineTitle),
                        onSelected: (_) =>
                            setSheetState(() => selectedProfile = p),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  _OemCompactPreviewBanner(
                    profile: selectedProfile,
                    numFmt: numFmt,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate:
                                insuranceExpiry ??
                                DateTime.now().add(const Duration(days: 365)),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setSheetState(() => insuranceExpiry = picked);
                          }
                        },
                        icon: const Icon(
                          Icons.verified_user_outlined,
                          size: 17,
                        ),
                        label: Text(
                          insuranceExpiry != null
                              ? 'BH TNDS: ${dateFmt.format(insuranceExpiry!)}'
                              : 'Cập nhật hạn Bảo hiểm TNDS',
                        ),
                      ),
                      if (selectedCategory.requiresPeriodicInspection)
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate:
                                  inspectionExpiry ??
                                  DateTime.now().add(const Duration(days: 365)),
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setSheetState(() => inspectionExpiry = picked);
                            }
                          },
                          icon: const Icon(Icons.fact_check_outlined, size: 17),
                          label: Text(
                            inspectionExpiry != null
                                ? 'Đăng kiểm: ${dateFmt.format(inspectionExpiry!)}'
                                : 'Cập nhật hạn Đăng kiểm ô tô',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Đóng'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: () {
                            bloc.add(
                              VehicleSpecProfileUpdated(
                                vehicle: vehicle,
                                category: selectedCategory,
                                modelProfileKey: selectedProfile.profileKey,
                                updatedName: nameCtrl.text,
                                updatedPlateNumber: plateCtrl.text,
                                insuranceExpiryDate: insuranceExpiry,
                                inspectionExpiryDate: inspectionExpiry,
                              ),
                            );
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('Áp dụng thông số'),
                        ),
                      ),
                    ],
                  ),
                  if (!vehicle.isFamilyShared ||
                      vehicle.ownerId.isEmpty ||
                      vehicle.ownerId == widget.userId) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      key: const Key('edit_sheet_delete_vehicle_btn'),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _confirmDeleteVehicle(context, vehicle);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Xóa phương tiện này khỏi danh sách'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
    nameCtrl.dispose();
    plateCtrl.dispose();
  }

  Future<void> _confirmDeleteVehicle(
    BuildContext context,
    VehicleEntity vehicle,
  ) async {
    final bloc = context.read<VehicleBloc>();
    final plateText = vehicle.plateNumber.trim().isEmpty
        ? 'chưa cập nhật biển số'
        : vehicle.displayPlateForViewer(widget.userId);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Xóa xe "${vehicle.name}"?'),
        content: Text(
          'Hồ sơ xe ($plateText) và các mốc nhắc bảo dưỡng của xe này sẽ được xóa khỏi danh sách. Các giao dịch chi tiêu đã lưu trong Sổ thu chi không bị ảnh hưởng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            key: const Key('confirm_delete_vehicle_dialog_btn'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Xóa xe'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _selectedIdx = 0;
        _watchedHistoryVehicleId = null;
      });
      bloc.add(VehicleDeleted(actorUserId: widget.userId, vehicle: vehicle));
    }
  }

  Future<void> _showMaintenanceSheet(
    BuildContext context,
    VehicleEntity vehicle,
    String? walletId, {
    MaintenanceComponentSpec? presetSpec,
  }) async {
    final profile = vehicle.maintenanceProfile;
    var selectedSpec = presetSpec ?? profile.components.firstOrNull;
    final titleCtrl = TextEditingController(
      text: selectedSpec?.title ?? 'Thay nhớt định kỳ',
    );
    final odoCtrl = TextEditingController(
      text: vehicle.currentOdometerKm.toString(),
    );
    final costCtrl = TextEditingController(
      text: (selectedSpec?.referenceCostMinor ?? 165000).toString(),
    );
    var deductWallet = walletId != null;
    final bloc = context.read<VehicleBloc>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final c = TammySemanticColors.of(ctx);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: LiquidGlassSheetFrame(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ghi nhận Bảo dưỡng · ${vehicle.name}',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: profile.components.map((comp) {
                        final picked = comp.key == selectedSpec?.key;
                        return ChoiceChip(
                          key: Key('maint_chip_${comp.key}'),
                          selected: picked,
                          label: Text(comp.title.split('(').first.trim()),
                          onSelected: (_) {
                            setSheetState(() {
                              selectedSpec = comp;
                              titleCtrl.text = comp.title;
                              costCtrl.text = comp.referenceCostMinor
                                  .toString();
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (selectedSpec != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: c.primarySubtle,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Định mức chuẩn: ${selectedSpec!.specDetail}',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 12.4,
                                fontWeight: FontWeight.w700,
                                color: c.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              selectedSpec!.technicianTip,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nội dung thực hiện',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: odoCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Số ODO lúc làm (km)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: costCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Chi phí (VND)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (walletId != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Tự động trừ chi phí vào Ví chính'),
                        value: deductWallet,
                        onChanged: (v) => setSheetState(() => deductWallet = v),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Hủy'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            key: const Key('maint_confirm_save_btn'),
                            onPressed: () {
                              final cost =
                                  VndAmount.tryParseInput(costCtrl.text) ?? 0;
                              final odo =
                                  int.tryParse(
                                    odoCtrl.text.replaceAll('.', ''),
                                  ) ??
                                  vehicle.currentOdometerKm;
                              bloc.add(
                                VehicleMaintenanceLogged(
                                  vehicle: vehicle,
                                  serviceTitle: titleCtrl.text,
                                  odometerKm: odo,
                                  costMinor: cost,
                                  componentKey: selectedSpec?.key,
                                  walletIdForExpense: deductWallet
                                      ? walletId
                                      : null,
                                ),
                              );
                              Navigator.of(ctx).pop();
                            },
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Lưu bảo dưỡng'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OemComponentChecklistRow extends StatelessWidget {
  final VehicleComponentStatus item;
  final NumberFormat numFmt;
  final VoidCallback onLogTap;

  const _OemComponentChecklistRow({
    required this.item,
    required this.numFmt,
    required this.onLogTap,
  });

  IconData _iconForKind(MaintenanceComponentKind kind) => switch (kind) {
    MaintenanceComponentKind.engineOil => Icons.oil_barrel_outlined,
    MaintenanceComponentKind.oilFilter => Icons.filter_alt_outlined,
    MaintenanceComponentKind.gearOil => Icons.settings_suggest_rounded,
    MaintenanceComponentKind.cvtBeltAndPulley => Icons.autorenew_rounded,
    MaintenanceComponentKind.chainAndSprocket => Icons.link_rounded,
    MaintenanceComponentKind.airFilter => Icons.air_rounded,
    MaintenanceComponentKind.sparkPlug => Icons.bolt_rounded,
    MaintenanceComponentKind.coolant => Icons.water_drop_outlined,
    MaintenanceComponentKind.brakesAndTires => Icons.tire_repair_outlined,
    MaintenanceComponentKind.evBatteryAndMotor =>
      Icons.battery_charging_full_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final spec = item.spec;
    final (tone, badgeIcon, badgeText) = switch (item.dueState) {
      VehicleDueState.overdue => (
        LifeOsAccentTone.coral,
        Icons.warning_amber_rounded,
        'Quá hạn ${numFmt.format(-item.remainingKm)} km',
      ),
      VehicleDueState.dueSoon => (
        LifeOsAccentTone.amber,
        Icons.schedule_rounded,
        'Còn ${numFmt.format(item.remainingKm)} km',
      ),
      VehicleDueState.healthy => (
        LifeOsAccentTone.emerald,
        Icons.check_circle_outline_rounded,
        'Còn ${numFmt.format(item.remainingKm)} km',
      ),
    };

    return InkWell(
      key: Key('component_row_${spec.key}'),
      borderRadius: BorderRadius.circular(14),
      onTap: onLogTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LifeOsIconSquircle(
                  icon: _iconForKind(spec.kind),
                  tone: tone,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            spec.title,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 14.2,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                          LifeOsStatusPill(
                            icon: badgeIcon,
                            label: badgeText,
                            tone: tone,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        spec.specDetail,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12.3,
                          fontWeight: FontWeight.w700,
                          color: c.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      LifeOsAnimatedProgressBar(
                        progressRatio: spec.intervalKm <= 0
                            ? 0.0
                            : ((spec.intervalKm - item.remainingKm) /
                                      spec.intervalKm)
                                  .clamp(0.04, 1.0),
                        color: switch (item.dueState) {
                          VehicleDueState.overdue => c.error,
                          VehicleDueState.dueSoon => c.warning,
                          VehicleDueState.healthy => c.primary,
                        },
                        height: 6.0,
                        semanticsLabel: 'Tiến độ hao mòn ${spec.title}',
                        semanticsValue: badgeText,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Mốc kế: ${numFmt.format(item.nextDueKm)} km (chu kỳ ${numFmt.format(spec.intervalKm)} km)',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 11.6,
                              color: c.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          Text(
                            '~${VndAmount.format(spec.referenceCostMinor)}',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 11.6,
                              fontWeight: FontWeight.w700,
                              color: c.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CarInspectionChecklistRow extends StatelessWidget {
  final DateTime? inspectionExpiryDate;
  final DateTime now;
  final DateFormat dateFmt;
  final VoidCallback onTap;

  const _CarInspectionChecklistRow({
    required this.inspectionExpiryDate,
    required this.now,
    required this.dateFmt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final remDays = inspectionExpiryDate?.difference(now).inDays;
    final tone = remDays == null
        ? LifeOsAccentTone.neutral
        : (remDays <= 0
              ? LifeOsAccentTone.coral
              : (remDays <= 30
                    ? LifeOsAccentTone.amber
                    : LifeOsAccentTone.emerald));

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LifeOsIconSquircle(
            icon: Icons.fact_check_outlined,
            tone: tone,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hạn đăng kiểm định kỳ (Ô tô)',
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 14.2,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  inspectionExpiryDate != null
                      ? 'Hạn đăng kiểm: ${dateFmt.format(inspectionExpiryDate!)}'
                      : 'Chạm để cập nhật ngày hết hạn đăng kiểm ô tô',
                  softWrap: true,
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
          LifeOsStatusPill(
            icon: Icons.calendar_today_outlined,
            label: remDays != null
                ? (remDays >= 0 ? 'Còn $remDays ngày' : 'Quá hạn ${-remDays}n')
                : 'Cập nhật',
            tone: tone,
          ),
        ],
      ),
    );
  }
}
