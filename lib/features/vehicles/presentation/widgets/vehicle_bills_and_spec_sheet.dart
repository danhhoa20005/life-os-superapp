import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vietnamese_search_matcher.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../domain/entities/vehicle_entities.dart';
import '../bloc/vehicle_bloc.dart';

class UnifiedRecurringBillsTab extends StatelessWidget {
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');

  final String userId;
  final List<RecurringBillEntity> bills;
  final String? defaultWalletId;
  final VoidCallback onAddBill;

  const UnifiedRecurringBillsTab({
    super.key,
    required this.userId,
    required this.bills,
    this.defaultWalletId,
    required this.onAddBill,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (bills.isEmpty)
              LifeOsMintHeroCard(
                child: Column(
                  children: [
                    const LifeOsIconSquircle(
                      icon: Icons.electric_bolt_rounded,
                      tone: LifeOsAccentTone.purple,
                      size: 50,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Chưa có hóa đơn định kỳ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Điện, nước, internet và phí định kỳ hằng tháng.',
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: onAddBill,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Thêm hóa đơn định kỳ'),
                    ),
                  ],
                ),
              )
            else
              ...bills.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LifeOsSoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const LifeOsIconSquircle(
                              icon: Icons.electric_bolt_rounded,
                              tone: LifeOsAccentTone.purple,
                              size: 42,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${b.title} · ${VndAmount.format(b.estimatedAmountMinor)}',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                      color: c.textPrimary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'Kỳ hạn kế tiếp: ${_dateFmt.format(b.nextDueDate)}',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: c.textSecondary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  if (b.hasAbnormalSpike) ...[
                                    const SizedBox(height: 4),
                                    const LifeOsStatusPill(
                                      icon: Icons.warning_amber_rounded,
                                      label: 'Tăng >= 25%',
                                      tone: LifeOsAccentTone.amber,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (b.familyId == null ||
                                b.ownerId.isEmpty ||
                                b.ownerId == userId)
                              IconButton(
                                key: Key('bill_delete_btn_${b.id}'),
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Xóa hóa đơn',
                                onPressed: () async {
                                  final bloc = context.read<VehicleBloc>();
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (dCtx) => AlertDialog(
                                      title: Text('Xóa "${b.title}"?'),
                                      content: const Text(
                                        'Hóa đơn định kỳ này sẽ được gỡ khỏi danh sách nhắc hạn hằng tháng.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(dCtx).pop(false),
                                          child: const Text('Giữ lại'),
                                        ),
                                        FilledButton(
                                          key: const Key(
                                            'confirm_delete_bill_dialog_btn',
                                          ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFFDC2626,
                                            ),
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () =>
                                              Navigator.of(dCtx).pop(true),
                                          child: const Text('Xóa'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    bloc.add(
                                      RecurringBillDeleted(
                                        actorUserId: userId,
                                        bill: b,
                                      ),
                                    );
                                  }
                                },
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 19,
                                  color: c.textSecondary,
                                ),
                              ),
                          ],
                        ),
                        if (defaultWalletId != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonal(
                              key: Key('bill_pay_btn_${b.id}'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                final bloc = context.read<VehicleBloc>();
                                final paidCtrl = TextEditingController(
                                  text: '${b.estimatedAmountMinor}',
                                );
                                final confirmedAmount = await showDialog<int>(
                                  context: context,
                                  builder: (dCtx) => AlertDialog(
                                    title: Text('Thanh toán: ${b.title}'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          'Dự kiến hằng tháng: ${VndAmount.format(b.estimatedAmountMinor)}. Nhập số tiền thực đóng kỳ này (hệ thống tự cảnh báo nếu tăng bất thường >= 25%):',
                                          style: Theme.of(
                                            dCtx,
                                          ).textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 10),
                                        TextField(
                                          key: const Key(
                                            'recurring_bill_paid_amount_input',
                                          ),
                                          controller: paidCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Số tiền thực đóng kỳ này (VND)',
                                          ),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(dCtx).pop(),
                                        child: const Text('Hủy'),
                                      ),
                                      FilledButton(
                                        key: const Key(
                                          'confirm_pay_recurring_bill_btn',
                                        ),
                                        onPressed: () {
                                          final parsed =
                                              VndAmount.tryParseInput(
                                                paidCtrl.text,
                                              ) ??
                                              b.estimatedAmountMinor;
                                          Navigator.of(dCtx).pop(
                                            parsed > 0
                                                ? parsed
                                                : b.estimatedAmountMinor,
                                          );
                                        },
                                        child: const Text('Xác nhận & Trừ ví'),
                                      ),
                                    ],
                                  ),
                                );
                                paidCtrl.dispose();
                                if (confirmedAmount != null) {
                                  bloc.add(
                                    RecurringBillPaid(
                                      userId: userId,
                                      bill: b,
                                      paidAmountMinor: confirmedAmount,
                                      walletId: defaultWalletId!,
                                    ),
                                  );
                                }
                              },
                              child: const Text('Thanh toán'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class VehicleSpecEncyclopediaSheetBody extends StatefulWidget {
  final ScrollController scrollController;

  const VehicleSpecEncyclopediaSheetBody({
    super.key,
    required this.scrollController,
  });

  @override
  State<VehicleSpecEncyclopediaSheetBody> createState() =>
      _VehicleSpecEncyclopediaSheetBodyState();
}

class _VehicleSpecEncyclopediaSheetBodyState
    extends State<VehicleSpecEncyclopediaSheetBody> {
  static final NumberFormat _numFmt = NumberFormat('#,###', 'vi_VN');

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  VehicleCategory? _selectedCategory;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _kvLine(BuildContext context, String label, String value) {
    final c = TammySemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 12.4,
            height: 1.35,
            color: c.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
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

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final hasActiveFilter =
        _selectedCategory != null || _searchQuery.trim().isNotEmpty;
    final filteredProfiles = MotorcycleSpecCatalog.allProfiles.where((p) {
      if (_selectedCategory != null && p.category != _selectedCategory) {
        return false;
      }
      return VietnameseSearchMatcher.matchesAny(_searchQuery, [
        p.modelLineTitle,
        p.category.displayLabel,
        p.engineTechSummary,
        p.oilGradeSpec,
        p.coolingSystem,
      ]);
    }).toList();

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Text(
          'Cẩm nang Thông số Bảo dưỡng Chuẩn hãng',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('vehicle_spec_search_field'),
          controller: _searchCtrl,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Tìm dòng xe, chuẩn nhớt',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    key: const Key('vehicle_spec_clear_btn'),
                    tooltip: 'Xóa tìm kiếm',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
          ),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ChoiceChip(
              key: const Key('vehicle_spec_filter_all'),
              label: Text(
                'Tất cả (${MotorcycleSpecCatalog.allProfiles.length})',
              ),
              selected: !hasActiveFilter,
              onSelected: (_) {
                _searchCtrl.clear();
                setState(() {
                  _selectedCategory = null;
                  _searchQuery = '';
                });
              },
            ),
            for (final cat in VehicleCategory.values)
              ChoiceChip(
                label: Text(cat.displayLabel),
                selected: _selectedCategory == cat,
                onSelected: (sel) =>
                    setState(() => _selectedCategory = sel ? cat : null),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (filteredProfiles.isEmpty)
          LifeOsSoftCard(
            child: Column(
              children: [
                Icon(Icons.search_off_rounded, size: 36, color: c.primary),
                const SizedBox(height: 8),
                Text(
                  'Không tìm thấy dòng xe khớp bộ lọc',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  key: const Key('vehicle_spec_reset_btn'),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {
                      _selectedCategory = null;
                      _searchQuery = '';
                    });
                  },
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: const Text('Xem tất cả'),
                ),
              ],
            ),
          )
        else
          ...filteredProfiles.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LifeOsSoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        LifeOsStatusPill(
                          icon: p.category.isMotorcycle
                              ? Icons.two_wheeler_rounded
                              : Icons.directions_car_filled_outlined,
                          label: p.category.displayLabel,
                          tone: LifeOsAccentTone.emerald,
                        ),
                        Text(
                          p.modelLineTitle,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      p.engineTechSummary,
                      softWrap: true,
                      style: TextStyle(fontSize: 12.2, color: c.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    _kvLine(context, 'Chuẩn nhớt', p.oilGradeSpec),
                    _kvLine(context, 'Dung tích nhớt máy', p.engineOilCapacity),
                    if (p.gearOilCapacity != null)
                      _kvLine(
                        context,
                        'Dung tích nhớt láp',
                        p.gearOilCapacity!,
                      ),
                    _kvLine(context, 'Làm mát', p.coolingSystem),
                    _kvLine(
                      context,
                      'Chu kỳ chính',
                      'Mỗi ${_numFmt.format(p.recommendedOilIntervalKm)} km (${p.recommendedIntervalDays} ngày)',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• ${p.firstBreakInNote}',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
