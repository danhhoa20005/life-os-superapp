import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/vietnamese_search_matcher.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../../transactions/presentation/bloc/transaction_state.dart';
import '../../domain/entities/pro_utilities_entities.dart';
import '../bloc/pro_utilities_bloc.dart';

/// Vietnamese Gift/Wedding Envelope Ledger & Smart Trip Packing Checklist.
class SocialLedgerTravelPage extends StatefulWidget {
  const SocialLedgerTravelPage({super.key});

  @override
  State<SocialLedgerTravelPage> createState() => _SocialLedgerTravelPageState();
}

class _SocialLedgerTravelPageState extends State<SocialLedgerTravelPage> {
  bool _showPackingTab = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _customPackCtrl = TextEditingController();
  String _searchQuery = '';
  String _directionFilter = 'all'; // 'all' | 'gave' | 'received'

  @override
  void dispose() {
    _searchCtrl.dispose();
    _customPackCtrl.dispose();
    super.dispose();
  }

  T? _maybeRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } catch (_) {
      return null;
    }
  }

  T? _maybeWatch<T>(BuildContext context) {
    try {
      return context.watch<T>();
    } catch (_) {
      return null;
    }
  }

  static const Map<String, List<String>> _tripTemplates = {
    'Du lịch Biển 3N2Đ': [
      'Căn cước công dân / Vé máy bay',
      'Sạc dự phòng & Cáp sạc điện thoại',
      'Kem chống nắng, kính râm & đồ bơi',
      'Thuốc cá nhân & băng cá nhân',
      'Tiền mặt lẻ & Thẻ ngân hàng',
    ],
    'Đi Công tác': [
      'Laptop, củ sạc & đầu chuyển HDMI',
      'Trang phục họp lịch sự & thẻ tên',
      'Căn cước / Hộ chiếu & Hóa đơn VAT',
      'Sạc dự phòng 10.000mAh',
    ],
    'Về quê Lễ Tết': [
      'Quà biếu Ông Bà / Nội Ngoại',
      'Phong bao lì xì mừng tuổi',
      'Giấy tờ xe, bằng lái & bảo hiểm TNDS',
      'Quần áo ấm / Đồ dùng cho bé',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = TammySemanticColors.of(context);
    final txListState = _maybeWatch<TransactionListBloc>(context)?.state;
    final wallets = txListState?.wallets ?? const <WalletEntity>[];
    final categories = txListState?.categories ?? const <CategoryEntity>[];
    final dateFmt = DateFormat('dd/MM/yyyy');

    return BlocListener<ProUtilitiesBloc, ProUtilitiesState>(
      listenWhen: (p, n) =>
          (n.failure != null && p.failure != n.failure) ||
          (n.message != null && p.message != n.message),
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
      child: Scaffold(
        body: LifeOsMintWaveCanvas(
          child: SafeArea(
            child: Column(
              children: [
                LifeOsTopBrandHeader(
                  title: 'Sổ Hiếu Hỷ & Hành lý',
                  showBackButton: true,
                  trailingAction: !_showPackingTab
                      ? IconButton.filledTonal(
                          tooltip: 'Ghi mừng mới',
                          onPressed: () => _showSaveGiftDialog(
                            context,
                            userId: user.id,
                            defaultWalletId: wallets.isNotEmpty
                                ? wallets.first.id
                                : null,
                            categories: categories,
                          ),
                          icon: const Icon(Icons.add_rounded),
                        )
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.maxContentWidth,
                    ),
                    child: LifeOsSegmentedPills<bool>(
                      selected: _showPackingTab,
                      options: const [
                        (false, 'Sổ Hiếu Hỷ', Icons.card_giftcard_rounded),
                        (true, 'Hành lý Chuyến đi', Icons.luggage_outlined),
                      ],
                      onChanged: (v) => setState(() => _showPackingTab = v),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: BlocBuilder<ProUtilitiesBloc, ProUtilitiesState>(
                    builder: (context, state) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppSpacing.maxContentWidth,
                          ),
                          child: _showPackingTab
                              ? _buildPackingTab(context, c, user.id, state)
                              : _buildGiftLedgerTab(
                                  context,
                                  c,
                                  user.id,
                                  state,
                                  dateFmt,
                                  wallets.isNotEmpty ? wallets.first.id : null,
                                  categories,
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGiftLedgerTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    ProUtilitiesState state,
    DateFormat dateFmt,
    String? defaultWalletId,
    List<CategoryEntity> categories,
  ) {
    final hasActiveFilter =
        _directionFilter != 'all' || _searchQuery.trim().isNotEmpty;
    final filtered = state.giftEntries.where((g) {
      if (_directionFilter == 'gave' && g.direction != GiftDirection.gave) {
        return false;
      }
      if (_directionFilter == 'received' &&
          g.direction != GiftDirection.received) {
        return false;
      }
      return VietnameseSearchMatcher.matchesAny(_searchQuery, [
        g.contactName,
        g.relationshipGroup,
        g.occasion.labelVi,
        g.note,
      ]);
    }).toList();

    final netReciprocity =
        state.totalGiftReceivedMinor - state.totalGiftGaveMinor;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        2,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        // 1. Reciprocity Summary Hero Card ("Có đi có lại")
        LifeOsMintHeroCard(
          child: IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Đã đi mừng',
                          style: TextStyle(
                            fontSize: 11.8,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          VndAmount.format(state.totalGiftGaveMinor),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: c.error,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(width: 12, color: c.separator),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Đã nhận mừng',
                          style: TextStyle(
                            fontSize: 11.8,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          VndAmount.format(state.totalGiftReceivedMinor),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: c.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(width: 12, color: c.separator),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Chênh lệch',
                          style: TextStyle(
                            fontSize: 11.8,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          VndAmount.format(netReciprocity, showPlus: true),
                          style: TextStyle(
                            fontSize: 15,
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
        ),
        const SizedBox(height: 12),

        // 2. Instant Contact Reciprocity Search
        TextField(
          key: const Key('gift_ledger_search_field'),
          controller: _searchCtrl,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Tìm bạn bè, dịp mừng',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    key: const Key('gift_ledger_clear_btn'),
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
              key: const Key('gift_filter_all'),
              label: Text('Tất cả (${state.giftEntries.length})'),
              selected:
                  _directionFilter == 'all' && _searchQuery.trim().isEmpty,
              onSelected: (_) {
                _searchCtrl.clear();
                setState(() {
                  _directionFilter = 'all';
                  _searchQuery = '';
                });
              },
            ),
            ChoiceChip(
              key: const Key('gift_filter_gave'),
              label: Text(
                'Đi mừng (${state.giftEntries.where((g) => g.direction == GiftDirection.gave).length})',
              ),
              selected: _directionFilter == 'gave',
              onSelected: (sel) =>
                  setState(() => _directionFilter = sel ? 'gave' : 'all'),
            ),
            ChoiceChip(
              key: const Key('gift_filter_received'),
              label: Text(
                'Nhận mừng (${state.giftEntries.where((g) => g.direction == GiftDirection.received).length})',
              ),
              selected: _directionFilter == 'received',
              onSelected: (sel) =>
                  setState(() => _directionFilter = sel ? 'received' : 'all'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (filtered.isEmpty)
          LifeOsSoftCard(
            child: Column(
              children: [
                BananaGlassIcon(
                  assetPath: AppAssets.icLifeSocialTravel,
                  fallbackIcon: hasActiveFilter && state.giftEntries.isNotEmpty
                      ? Icons.search_off_rounded
                      : Icons.volunteer_activism_outlined,
                  size: 48,
                ),
                const SizedBox(height: 10),
                Text(
                  hasActiveFilter && state.giftEntries.isNotEmpty
                      ? 'Không tìm thấy mục ghi khớp bộ lọc'
                      : 'Chưa có mục ghi Hiếu Hỷ nào',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasActiveFilter && state.giftEntries.isNotEmpty
                      ? 'Hãy xóa từ khóa tìm kiếm hoặc chọn Tất cả để xem lại toàn bộ sổ mừng.'
                      : 'Ghi tiền mừng hai chiều để tiện tra cứu khi cần đáp lễ.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                ),
                if (hasActiveFilter && state.giftEntries.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    key: const Key('gift_ledger_reset_filter_btn'),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _directionFilter = 'all';
                        _searchQuery = '';
                      });
                    },
                    icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                    label: const Text('Xóa bộ lọc'),
                  ),
                ],
              ],
            ),
          )
        else
          ...filtered.map((g) {
            final isReceived = g.direction == GiftDirection.received;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LifeOsSoftCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LifeOsIconSquircle(
                          icon: isReceived
                              ? Icons.call_received_rounded
                              : Icons.call_made_rounded,
                          tone: isReceived
                              ? LifeOsAccentTone.emerald
                              : LifeOsAccentTone.coral,
                          size: 42,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                g.contactName,
                                softWrap: true,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                '${g.occasion.labelVi} · ${g.relationshipGroup} · ${dateFmt.format(g.eventDate)}',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              if (g.note.isNotEmpty)
                                Text(
                                  g.note,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.textPrimary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          flex: 0,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 126),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                '${isReceived ? "+" : "-"}${VndAmount.format(g.amountMinor)}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: isReceived ? c.primary : c.error,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        LifeOsStatusPill(
                          label: isReceived ? 'Nhận mừng' : 'Đi mừng',
                          tone: isReceived
                              ? LifeOsAccentTone.emerald
                              : LifeOsAccentTone.coral,
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: Key('edit_gift_${g.id}'),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Sửa khoản mừng',
                              onPressed: () => _showSaveGiftDialog(
                                context,
                                userId: userId,
                                existing: g,
                                defaultWalletId: defaultWalletId,
                                categories: categories,
                              ),
                              icon: Icon(
                                Icons.edit_outlined,
                                size: 19,
                                color: c.textSecondary,
                              ),
                            ),
                            IconButton(
                              key: Key('delete_gift_${g.id}'),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Xóa khoản mừng',
                              onPressed: () async {
                                final ok = await showDestructiveConfirmDialog(
                                  context: context,
                                  title: 'Xóa mục "${g.contactName}"?',
                                  message:
                                      'Khoản ${isReceived ? "nhận mừng" : "đi mừng"} ${VndAmount.format(g.amountMinor)} sẽ bị xóa khỏi Sổ Hiếu Hỷ.',
                                  confirmLabel: 'Xóa',
                                );
                                if (ok && context.mounted) {
                                  context.read<ProUtilitiesBloc>().add(
                                    GiftLedgerEntryDeleted(
                                      userId: userId,
                                      entryId: g.id,
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
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

        const SizedBox(height: 14),
        LifeOsPrimaryCtaButton(
          icon: Icons.add_rounded,
          label: 'Ghi khoản Đi mừng / Nhận mừng',
          onPressed: () => _showSaveGiftDialog(
            context,
            userId: userId,
            defaultWalletId: defaultWalletId,
            categories: categories,
          ),
        ),
      ],
    );
  }

  Widget _buildPackingTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    ProUtilitiesState state,
  ) {
    final items = state.packingItems;
    final checkedCount = items.where((e) => e.checked).length;
    final pct = items.isEmpty
        ? 0
        : ((checkedCount * 100) / items.length).round();
    final activeTrip = items.isNotEmpty
        ? items.first.tripName
        : 'Chuyến đi cá nhân';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        2,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        LifeOsMintHeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BananaGlassIcon(
                    assetPath: AppAssets.icLifeSocialTravel,
                    fallbackIcon: Icons.luggage_outlined,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Danh sách Đồ mang theo',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          items.isEmpty
                              ? 'Chưa chọn mẫu chuyến đi'
                              : '$activeTrip ($checkedCount/${items.length} món đã xếp · $pct%)',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tripTemplates.entries.map((entry) {
                  return ActionChip(
                    avatar: Icon(
                      Icons.flight_takeoff_rounded,
                      size: 16,
                      color: c.primary,
                    ),
                    label: Text(entry.key),
                    onPressed: () async {
                      if (checkedCount > 0) {
                        final ok = await showDestructiveConfirmDialog(
                          context: context,
                          title: 'Nạp mẫu "${entry.key}"?',
                          message:
                              'Danh sách hiện tại đang có $checkedCount món đã đánh dấu hoàn thành sẽ bị thay thế hoàn toàn bởi mẫu mới.',
                          confirmLabel: 'Nạp mẫu mới',
                        );
                        if (!ok || !context.mounted) return;
                      }
                      context.read<ProUtilitiesBloc>().add(
                        PackingTemplateSeeded(
                          userId: userId,
                          tripName: entry.key,
                          itemTitles: entry.value,
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('packing_custom_item_input'),
                      controller: _customPackCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Thêm món đồ cá nhân lẻ',
                        hintText: 'VD: Ô che nắng, thuốc say xe',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    key: const Key('add_custom_packing_item_btn'),
                    onPressed: () {
                      final title = _customPackCtrl.text.trim();
                      if (title.isEmpty) {
                        LifeOsTopToast.show(
                          context,
                          'Vui lòng nhập tên vật dụng cần mang.',
                          kind: LifeOsToastKind.warning,
                        );
                        return;
                      }
                      context.read<ProUtilitiesBloc>().add(
                        PackingItemAdded(
                          userId: userId,
                          tripName: activeTrip,
                          title: title,
                        ),
                      );
                      _customPackCtrl.clear();
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Thêm'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          LifeOsSoftCard(
            child: Column(
              children: [
                const BananaGlassIcon(
                  assetPath: AppAssets.icLifeSocialTravel,
                  fallbackIcon: Icons.luggage_outlined,
                  size: 46,
                ),
                const SizedBox(height: 10),
                Text(
                  'Chưa có vật dụng nào trong hành lý',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Chọn một mẫu chuyến đi phía trên hoặc thêm món đồ cá nhân lẻ để chuẩn bị trước giờ khởi hành.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                ),
              ],
            ),
          )
        else
          LifeOsSoftCard(
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: Checkbox(
                          activeColor: c.primary,
                          value: items[i].checked,
                          onChanged: (_) =>
                              context.read<ProUtilitiesBloc>().add(
                                PackingItemToggled(
                                  userId: userId,
                                  item: items[i],
                                ),
                              ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => context.read<ProUtilitiesBloc>().add(
                            PackingItemToggled(userId: userId, item: items[i]),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              items[i].title,
                              softWrap: true,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                decoration: items[i].checked
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: items[i].checked
                                    ? c.textSecondary
                                    : c.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        key: Key('delete_packing_item_${items[i].id}'),
                        tooltip: 'Xóa món',
                        onPressed: () => context.read<ProUtilitiesBloc>().add(
                          PackingItemDeleted(
                            userId: userId,
                            itemId: items[i].id,
                          ),
                        ),
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _showSaveGiftDialog(
    BuildContext context, {
    required String userId,
    GiftLedgerEntryEntity? existing,
    String? defaultWalletId,
    required List<CategoryEntity> categories,
  }) async {
    final proBloc = context.read<ProUtilitiesBloc>();
    final txActionBloc = _maybeRead<TransactionActionBloc>(context);
    await showDialog<void>(
      context: context,
      builder: (_) => _SaveGiftLedgerDialog(
        proBloc: proBloc,
        txActionBloc: txActionBloc,
        userId: userId,
        existing: existing,
        defaultWalletId: defaultWalletId,
        categories: categories,
      ),
    );
  }
}

class _SaveGiftLedgerDialog extends StatefulWidget {
  const _SaveGiftLedgerDialog({
    required this.proBloc,
    required this.txActionBloc,
    required this.userId,
    this.existing,
    this.defaultWalletId,
    required this.categories,
  });

  final ProUtilitiesBloc proBloc;
  final TransactionActionBloc? txActionBloc;
  final String userId;
  final GiftLedgerEntryEntity? existing;
  final String? defaultWalletId;
  final List<CategoryEntity> categories;

  @override
  State<_SaveGiftLedgerDialog> createState() => _SaveGiftLedgerDialogState();
}

class _SaveGiftLedgerDialogState extends State<_SaveGiftLedgerDialog> {
  static const List<String> _allowedGroups = <String>[
    'Đồng nghiệp',
    'Bạn học',
    'Họ hàng',
    'Hàng xóm / Đối tác',
  ];

  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.existing?.contactName ?? '',
  );
  late final TextEditingController _amtCtrl = TextEditingController(
    text: widget.existing != null ? '${widget.existing!.amountMinor}' : '',
  );
  late final TextEditingController _noteCtrl = TextEditingController(
    text: widget.existing?.note ?? '',
  );

  late String _group = () {
    final g = widget.existing?.relationshipGroup ?? 'Đồng nghiệp';
    return _allowedGroups.contains(g) ? g : 'Đồng nghiệp';
  }();
  late GiftDirection _direction =
      widget.existing?.direction ?? GiftDirection.gave;
  late GiftOccasion _occasion =
      widget.existing?.occasion ?? GiftOccasion.wedding;
  late DateTime _eventDate = widget.existing?.eventDate ?? DateTime.now();
  late bool _recordToWallet =
      widget.existing == null && widget.defaultWalletId != null;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isEdit = existing != null;
    final dateFmt = DateFormat('dd/MM/yyyy');

    return AlertDialog(
      title: Text(isEdit ? 'Sửa Sổ Hiếu Hỷ' : 'Ghi Sổ Hiếu Hỷ'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LifeOsSegmentedPills<GiftDirection>(
              selected: _direction,
              options: const [
                (GiftDirection.gave, 'Đi mừng', Icons.call_made_rounded),
                (
                  GiftDirection.received,
                  'Nhận mừng',
                  Icons.call_received_rounded,
                ),
              ],
              onChanged: _isSubmitting
                  ? (_) {}
                  : (v) => setState(() => _direction = v),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('gift_contact_name_input'),
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Họ tên người mừng / gia chủ',
                hintText: 'VD: Nguyễn Tuấn Anh',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<GiftOccasion>(
              isExpanded: true,
              initialValue: _occasion,
              decoration: const InputDecoration(labelText: 'Dịp lễ / Sự kiện'),
              items: GiftOccasion.values
                  .map(
                    (o) => DropdownMenuItem(
                      value: o,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(o.labelVi),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _isSubmitting
                  ? null
                  : (v) {
                      if (v != null) setState(() => _occasion = v);
                    },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _group,
              decoration: const InputDecoration(labelText: 'Nhóm quan hệ'),
              items: const [
                DropdownMenuItem(
                  value: 'Đồng nghiệp',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('Đồng nghiệp'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Bạn học',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('Bạn học'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Họ hàng',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('Họ hàng Nội Ngoại'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Hàng xóm / Đối tác',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('Hàng xóm / Đối tác'),
                  ),
                ),
              ],
              onChanged: _isSubmitting
                  ? null
                  : (v) {
                      if (v != null) setState(() => _group = v);
                    },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('gift_event_date_btn'),
              onPressed: _isSubmitting
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _eventDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2040),
                      );
                      if (picked != null && mounted) {
                        setState(() => _eventDate = picked);
                      }
                    },
              icon: const Icon(Icons.event_rounded, size: 17),
              label: Text('Ngày sự kiện: ${dateFmt.format(_eventDate)}'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('gift_amount_input'),
              controller: _amtCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền mừng (VND)',
                hintText: 'VD: 1000000',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Ghi chú thêm (VD: Mừng thêm 1 chỉ vàng)',
              ),
            ),
            if (!isEdit &&
                widget.defaultWalletId != null &&
                widget.txActionBloc != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Đồng thời ghi Thu/Chi vào Ví'),
                value: _recordToWallet,
                onChanged: _isSubmitting
                    ? null
                    : (v) => setState(() => _recordToWallet = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('submit_gift_button'),
          onPressed: _isSubmitting
              ? null
              : () async {
                  final contact = _nameCtrl.text.trim();
                  final amt = VndAmount.tryParseInput(_amtCtrl.text) ?? 0;
                  if (contact.length < 2 || amt <= 0) {
                    LifeOsTopToast.show(
                      context,
                      'Vui lòng nhập tên người mừng (tối thiểu 2 ký tự) và số tiền > 0 ₫.',
                      kind: LifeOsToastKind.warning,
                    );
                    return;
                  }
                  if (!isEdit &&
                      _recordToWallet &&
                      widget.defaultWalletId != null &&
                      widget.txActionBloc != null) {
                    setState(() => _isSubmitting = true);
                    final isRecv = _direction == GiftDirection.received;
                    final expenseCatName = widget.categories.any(
                            (c) => c.name == 'Hiếu hỉ & Đối ngoại',
                          )
                        ? 'Hiếu hỉ & Đối ngoại'
                        : 'Chi tiêu khác';
                    final txRes = await widget.txActionBloc!
                        .submitAndAwaitCreate(
                          TransactionCreateSubmitted(
                            operationId: const Uuid().v4(),
                            userId: widget.userId,
                            walletId: widget.defaultWalletId!,
                            categoryName: isRecv
                                ? 'Thu nhập khác'
                                : expenseCatName,
                            kind: isRecv
                                ? TransactionKind.income
                                : TransactionKind.expense,
                            amountMinor: amt,
                            merchant: '${_occasion.labelVi} - $contact',
                            note: _noteCtrl.text.trim(),
                            occurredAt: _eventDate,
                          ),
                        );
                    if (!context.mounted) return;
                    if (txRes.status != ActionStatus.success) {
                      setState(() => _isSubmitting = false);
                      LifeOsTopToast.show(
                        context,
                        txRes.failure?.message ??
                            'Không thể ghi giao dịch vào Ví. Vui lòng thử lại.',
                        kind: LifeOsToastKind.error,
                      );
                      return;
                    }
                  }

                  if (isEdit) {
                    widget.proBloc.add(
                      GiftLedgerEntryUpdated(
                        userId: widget.userId,
                        entryId: existing.id,
                        contactName: contact,
                        relationshipGroup: _group,
                        direction: _direction,
                        occasion: _occasion,
                        amountMinor: amt,
                        eventDate: _eventDate,
                        note: _noteCtrl.text.trim(),
                      ),
                    );
                  } else {
                    widget.proBloc.add(
                      GiftLedgerEntrySubmitted(
                        userId: widget.userId,
                        contactName: contact,
                        relationshipGroup: _group,
                        direction: _direction,
                        occasion: _occasion,
                        amountMinor: amt,
                        eventDate: _eventDate,
                        note: _noteCtrl.text.trim(),
                      ),
                    );
                  }
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(isEdit ? 'Lưu thay đổi' : 'Lưu sổ'),
        ),
      ],
    );
  }
}
