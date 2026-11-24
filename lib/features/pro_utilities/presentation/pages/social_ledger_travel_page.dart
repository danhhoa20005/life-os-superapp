import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vietnamese_search_matcher.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../domain/entities/pro_utilities_entities.dart';
import '../bloc/pro_utilities_bloc.dart';

/// Replaces paid Vietnamese Gift/Wedding Envelope Ledgers & Tripsy Packing Checklists.
class SocialLedgerTravelPage extends StatefulWidget {
  const SocialLedgerTravelPage({super.key});

  @override
  State<SocialLedgerTravelPage> createState() => _SocialLedgerTravelPageState();
}

class _SocialLedgerTravelPageState extends State<SocialLedgerTravelPage> {
  bool _showPackingTab = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _directionFilter = 'all'; // 'all' | 'gave' | 'received'

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    final dateFmt = DateFormat('dd/MM/yyyy');

    return BlocListener<ProUtilitiesBloc, ProUtilitiesState>(
      listenWhen: (p, c) => p.failure != c.failure || p.message != c.message,
      listener: (context, state) {
        if (state.failure != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text('⚠ ${state.failure!.message}')),
          );
        } else if (state.message != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text('✓ ${state.message!}')),
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
                          onPressed: () => _showAddGiftDialog(
                            context,
                            userId: user.id,
                            defaultWalletId: wallets.isNotEmpty
                                ? wallets.first.id
                                : null,
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
              selected: _directionFilter == 'all' && _searchQuery.trim().isEmpty,
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
                LifeOsIconSquircle(
                  icon: hasActiveFilter && state.giftEntries.isNotEmpty
                      ? Icons.search_off_rounded
                      : Icons.volunteer_activism_outlined,
                  tone: LifeOsAccentTone.purple,
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
                child: Row(
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
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            '${g.occasion.labelVi} · ${g.relationshipGroup} · ${dateFmt.format(g.eventDate)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textSecondary,
                            ),
                          ),
                          if (g.note.isNotEmpty)
                            Text(
                              g.note,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textPrimary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${isReceived ? "+" : "-"}${VndAmount.format(g.amountMinor)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isReceived ? c.primary : c.error,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        LifeOsStatusPill(
                          label: isReceived ? 'Nhận mừng' : 'Đi mừng',
                          tone: isReceived
                              ? LifeOsAccentTone.emerald
                              : LifeOsAccentTone.coral,
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
          onPressed: () => _showAddGiftDialog(
            context,
            userId: userId,
            defaultWalletId: defaultWalletId,
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
        : 'Chưa chọn chuyến đi';

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
              Text(
                'Danh sách Đồ mang theo',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Đang mở: $activeTrip ($checkedCount/${items.length} món đã xếp · $pct%)',
                style: TextStyle(fontSize: 12.5, color: c.textSecondary),
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
                    onPressed: () => context.read<ProUtilitiesBloc>().add(
                      PackingTemplateSeeded(
                        userId: userId,
                        tripName: entry.key,
                        itemTitles: entry.value,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          LifeOsSoftCard(
            child: Text(
              'Chọn loại chuyến đi phía trên để tạo danh sách đồ mang theo.',
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          )
        else
          LifeOsSoftCard(
            child: Column(
              children: items.map((it) {
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: c.primary,
                  value: it.checked,
                  title: Text(
                    it.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: it.checked
                          ? TextDecoration.lineThrough
                          : null,
                      color: it.checked ? c.textSecondary : c.textPrimary,
                    ),
                  ),
                  onChanged: (_) => context.read<ProUtilitiesBloc>().add(
                    PackingItemToggled(userId: userId, item: it),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Future<void> _showAddGiftDialog(
    BuildContext context, {
    required String userId,
    String? defaultWalletId,
  }) async {
    final nameCtrl = TextEditingController();
    final amtCtrl = TextEditingController(text: '1000000');
    final noteCtrl = TextEditingController();
    var group = 'Đồng nghiệp';
    var direction = GiftDirection.gave;
    var occasion = GiftOccasion.wedding;
    var recordToWallet = defaultWalletId != null;

    final proBloc = context.read<ProUtilitiesBloc>();
    final txActionBloc = context.read<TransactionActionBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Ghi Sổ Hiếu Hỷ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LifeOsSegmentedPills<GiftDirection>(
                  selected: direction,
                  options: const [
                    (GiftDirection.gave, 'Đi mừng', Icons.call_made_rounded),
                    (
                      GiftDirection.received,
                      'Nhận mừng',
                      Icons.call_received_rounded,
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => direction = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('gift_contact_name_input'),
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Họ tên người mừng / gia chủ',
                    hintText: 'VD: Nguyễn Tuấn Anh',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<GiftOccasion>(
                  isExpanded: true,
                  initialValue: occasion,
                  decoration: const InputDecoration(
                    labelText: 'Dịp lễ / Sự kiện',
                  ),
                  items: GiftOccasion.values
                      .map(
                        (o) =>
                            DropdownMenuItem(value: o, child: Text(o.labelVi)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => occasion = v);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: group,
                  decoration: const InputDecoration(labelText: 'Nhóm quan hệ'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Đồng nghiệp',
                      child: Text('Đồng nghiệp'),
                    ),
                    DropdownMenuItem(value: 'Bạn học', child: Text('Bạn học')),
                    DropdownMenuItem(
                      value: 'Họ hàng',
                      child: Text('Họ hàng Nội Ngoại'),
                    ),
                    DropdownMenuItem(
                      value: 'Hàng xóm / Đối tác',
                      child: Text('Hàng xóm / Đối tác'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => group = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('gift_amount_input'),
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Số tiền mừng (VND)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú thêm (VD: Mừng thêm 1 chỉ vàng)',
                  ),
                ),
                if (defaultWalletId != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Đồng thời ghi Thu/Chi vào Ví'),
                    value: recordToWallet,
                    onChanged: (v) => setDialogState(() => recordToWallet = v),
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
              key: const Key('submit_gift_button'),
              onPressed: () {
                final contact = nameCtrl.text.trim();
                final amt = VndAmount.tryParseInput(amtCtrl.text) ?? 0;
                if (contact.length < 2 || amt <= 0) {
                  LifeOsTopToast.show(
                    ctx,
                    'Vui lòng nhập tên người mừng (tối thiểu 2 ký tự) và số tiền > 0 ₫.',
                    kind: LifeOsToastKind.warning,
                  );
                  return;
                }
                proBloc.add(
                  GiftLedgerEntrySubmitted(
                    userId: userId,
                    contactName: contact,
                    relationshipGroup: group,
                    direction: direction,
                    occasion: occasion,
                    amountMinor: amt,
                    note: noteCtrl.text.trim(),
                  ),
                );
                if (recordToWallet && defaultWalletId != null && amt > 0) {
                  txActionBloc.add(
                    TransactionCreateSubmitted(
                      operationId: const Uuid().v4(),
                      userId: userId,
                      walletId: defaultWalletId,
                      categoryName: 'Chi tiêu khác',
                      kind: direction == GiftDirection.received
                          ? TransactionKind.income
                          : TransactionKind.expense,
                      amountMinor: amt,
                      merchant: '${occasion.labelVi} - $contact',
                      note: noteCtrl.text.trim(),
                      occurredAt: DateTime.now(),
                    ),
                  );
                }
                Navigator.of(ctx).pop();
              },
              child: const Text('Lưu sổ'),
            ),
          ],
        ),
      ),
    );
  }
}
