import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../domain/entities/daily_life_entities.dart';
import '../bloc/daily_life_bloc.dart';

class KitchenGroceriesPage extends StatefulWidget {
  const KitchenGroceriesPage({super.key});

  @override
  State<KitchenGroceriesPage> createState() => _KitchenGroceriesPageState();
}

class _KitchenGroceriesPageState extends State<KitchenGroceriesPage> {
  String _tab = 'basket';
  int _featuredComboIndex = 0;

  static const List<
    ({String name, String qty, GroceryAisle aisle, int priceMinor})
  >
  _quickMarketChips = [
    (
      name: 'Trứng gà ta vỉ 10 quả',
      qty: '1 vỉ',
      aisle: GroceryAisle.meatSeafood,
      priceMinor: 36000,
    ),
    (
      name: 'Thịt ba rọi heo CP',
      qty: '500g',
      aisle: GroceryAisle.meatSeafood,
      priceMinor: 85000,
    ),
    (
      name: 'Rau cải ngọt & hành ngò',
      qty: '2 bó',
      aisle: GroceryAisle.produce,
      priceMinor: 22000,
    ),
    (
      name: 'Sữa tươi không đường 1L',
      qty: '1 hộp',
      aisle: GroceryAisle.meatSeafood,
      priceMinor: 34000,
    ),
    (
      name: 'Gạo thơm ST25 túi 5kg',
      qty: '1 túi',
      aisle: GroceryAisle.pantry,
      priceMinor: 165000,
    ),
    (
      name: 'Giấy vệ sinh & Nước rửa chén',
      qty: '1 combo',
      aisle: GroceryAisle.household,
      priceMinor: 68000,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final userId = user?.id ?? '';
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    final primaryWalletId = wallets.isNotEmpty
        ? wallets.first.id
        : 'wallet_cash_default';

    return BlocConsumer<DailyLifeBloc, DailyLifeState>(
      listenWhen: (p, n) =>
          p.successBanner != n.successBanner || p.failure != n.failure,
      listener: (context, state) {
        if (state.successBanner != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text(state.successBanner!)),
          );
        } else if (state.failure != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text(state.failure!.message)),
          );
        }
      },
      builder: (context, state) {
        final snap = state.snapshot;
        final shoppingList = snap.groceryItems
            .where((g) => !g.inFridgeStorage)
            .toList();
        final fridgeList = snap.groceryItems
            .where((g) => g.inFridgeStorage)
            .toList();

        return Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              child: Column(
                children: [
                  const LifeOsTopBrandHeader(
                    title: 'Bếp & Đi chợ Thông minh',
                    showBackButton: true,
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppSpacing.maxContentWidth,
                        ),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            4,
                            AppSpacing.md,
                            AppSpacing.xxl,
                          ),
                          children: [
                            // Hero Summary Card
                            LifeOsMintHeroCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.shopping_basket_rounded,
                                        tone: LifeOsAccentTone.emerald,
                                        solidFill: true,
                                        size: 42,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Bếp Gia Đình & Chi Tiêu Chợ',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              snap.mealPlans.isNotEmpty
                                                  ? 'Thực đơn hôm nay: ${snap.mealPlans.first.lunch}'
                                                  : 'Lên thực đơn trước khi đi chợ giúp giảm 25% chi tiêu thừa',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12.2,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  IntrinsicHeight(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${snap.pendingGroceriesCount} món',
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w800,
                                                  color: c.primary,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                'Cần mua thêm',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: c.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        VerticalDivider(
                                          width: 16,
                                          color: c.separator,
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                VndAmount.format(
                                                  snap.pendingGroceriesMinor +
                                                      snap.boughtGroceriesMinor,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w800,
                                                  color: c.textPrimary,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                'Dự toán giỏ chợ',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: c.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        VerticalDivider(
                                          width: 16,
                                          color: c.separator,
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${fridgeList.length} món',
                                                style: const TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF0EA5E9),
                                                  fontFeatures: [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                'Trong tủ lạnh',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: c.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            LifeOsSegmentedPills<String>(
                              selected: _tab,
                              onChanged: (v) => setState(() => _tab = v),
                              options: const [
                                (
                                  'basket',
                                  'Giỏ đi chợ',
                                  Icons.shopping_cart_outlined,
                                ),
                                (
                                  'meals',
                                  'Ăn gì hôm nay',
                                  Icons.restaurant_menu_rounded,
                                ),
                                ('fridge', 'Tủ lạnh', Icons.kitchen_outlined),
                              ],
                            ),
                            const SizedBox(height: 14),

                            if (_tab == 'basket')
                              _buildBasketTab(
                                context,
                                c,
                                userId,
                                primaryWalletId,
                                shoppingList,
                                snap.boughtGroceriesMinor,
                              )
                            else if (_tab == 'meals')
                              _buildMealsTab(context, c, userId, snap)
                            else
                              _buildFridgeTab(context, c, userId, fridgeList),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBasketTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    String primaryWalletId,
    List<SmartGroceryItemEntity> shoppingList,
    int boughtMinor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chạm để bỏ nhanh vào Giỏ đi chợ',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickMarketChips.map((chip) {
            return ActionChip(
              avatar: Icon(
                Icons.add_shopping_cart_rounded,
                size: 15,
                color: c.primary,
              ),
              label: Text(
                '${chip.name} (${VndAmount.format(chip.priceMinor)})',
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: userId.isEmpty
                  ? null
                  : () {
                      context.read<DailyLifeBloc>().add(
                        GroceryItemAdded(
                          userId: userId,
                          name: chip.name,
                          quantityLabel: chip.qty,
                          aisle: chip.aisle,
                          estimatedMinor: chip.priceMinor,
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
              child: OutlinedButton.icon(
                key: const Key('open_add_grocery_btn'),
                onPressed: userId.isEmpty
                    ? null
                    : () => _showAddGrocerySheet(
                        context,
                        userId,
                        inFridge: false,
                      ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Thêm món tự chọn'),
              ),
            ),
            if (boughtMinor > 0) ...[
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('checkout_grocery_to_wallet_btn'),
                  onPressed: userId.isEmpty
                      ? null
                      : () {
                          context.read<TransactionActionBloc>().add(
                            TransactionCreateSubmitted(
                              operationId:
                                  'groc_${DateTime.now().millisecondsSinceEpoch}',
                              userId: userId,
                              walletId: primaryWalletId,
                              categoryId: 'cat_food',
                              categoryName: 'Ăn uống',
                              kind: TransactionKind.expense,
                              amountMinor: boughtMinor,
                              merchant: 'Đi chợ & Thực phẩm Bếp gia đình',
                              note: 'Chốt từ Giỏ đi chợ thông minh LifeOS',
                              occurredAt: DateTime.now(),
                            ),
                          );
                          context.read<DailyLifeBloc>().add(
                            BoughtGroceriesCleared(userId),
                          );
                        },
                  icon: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                  ),
                  label: Text('Ghi Ví ${VndAmount.format(boughtMinor)}'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        if (shoppingList.isEmpty)
          LifeOsSoftCard(
            child: Column(
              children: [
                Icon(Icons.shopping_bag_outlined, size: 40, color: c.primary),
                const SizedBox(height: 8),
                Text(
                  'Giỏ đi chợ hôm nay đang trống',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bấm vào các món gợi ý ở trên hoặc qua tab "Ăn gì hôm nay" để đẩy toàn bộ nguyên liệu cả ngày vào giỏ chỉ với 1 chạm.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                ),
              ],
            ),
          )
        else
          ...shoppingList.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LifeOsSoftCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                onTap: () => context.read<DailyLifeBloc>().add(
                  GroceryItemBoughtToggled(userId: userId, item: item),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: item.isBought,
                      onChanged: (_) => context.read<DailyLifeBloc>().add(
                        GroceryItemBoughtToggled(userId: userId, item: item),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              decoration: item.isBought
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: item.isBought
                                  ? c.textSecondary
                                  : c.textPrimary,
                            ),
                          ),
                          Text(
                            '${item.quantityLabel} · ${item.aisle.label}',
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      VndAmount.format(item.estimatedMinor),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: c.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => context.read<DailyLifeBloc>().add(
                        GroceryItemDeleted(userId: userId, itemId: item.id),
                      ),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildMealsTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    DailyLifeSnapshot snap,
  ) {
    const combos = VietnameseMealSuggestionCatalog.presets;
    final activeCombo = combos[_featuredComboIndex % combos.length];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const LifeOsIconSquircle(
                    icon: Icons.casino_outlined,
                    tone: LifeOsAccentTone.amber,
                    size: 40,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeCombo.title,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          activeCombo.regionStyle,
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _featuredComboIndex =
                          (_featuredComboIndex + 1) % combos.length,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Đổi món'),
                  ),
                ],
              ),
              const Divider(height: 20),
              _MealSlotLine(slot: 'Sáng', dish: activeCombo.breakfast),
              const SizedBox(height: 6),
              _MealSlotLine(slot: 'Trưa', dish: activeCombo.lunch),
              const SizedBox(height: 6),
              _MealSlotLine(slot: 'Tối', dish: activeCombo.dinner),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  LifeOsStatusPill(
                    icon: Icons.payments_outlined,
                    label:
                        'Chi phí ~ ${VndAmount.format(activeCombo.estimatedCostMinor)}/ngày',
                    tone: LifeOsAccentTone.emerald,
                  ),
                  LifeOsStatusPill(
                    icon: Icons.bolt_rounded,
                    label: '~ ${activeCombo.estimatedKcal} kcal',
                    tone: LifeOsAccentTone.blue,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LifeOsPrimaryCtaButton(
                key: const Key('apply_meal_combo_btn'),
                label: 'Chốt Thực Đơn & Đẩy Nguyên Liệu Vào Giỏ Chợ',
                icon: Icons.playlist_add_check_circle_outlined,
                onPressed: userId.isEmpty
                    ? null
                    : () {
                        context.read<DailyLifeBloc>().add(
                          MealComboAppliedToGroceries(
                            userId: userId,
                            combo: activeCombo,
                          ),
                        );
                        setState(() => _tab = 'basket');
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Tất cả thực đơn gia đình gợi ý (${combos.length})',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ...combos.asMap().entries.map((entry) {
          final idx = entry.key;
          final combo = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LifeOsSoftCard(
              padding: const EdgeInsets.all(13),
              onTap: () => setState(() => _featuredComboIndex = idx),
              child: Row(
                children: [
                  LifeOsIconSquircle(
                    icon: Icons.soup_kitchen_outlined,
                    tone: idx == _featuredComboIndex
                        ? LifeOsAccentTone.emerald
                        : LifeOsAccentTone.neutral,
                    size: 38,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          combo.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.8,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          combo.lunch,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    VndAmount.format(combo.estimatedCostMinor),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.8,
                      color: c.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFridgeTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    List<SmartGroceryItemEntity> fridgeList,
  ) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LifeOsPrimaryCtaButton(
          label: '+ Cất thực phẩm tươi vào Tủ lạnh (Theo dõi hạn)',
          icon: Icons.kitchen_rounded,
          onPressed: userId.isEmpty
              ? null
              : () => _showAddGrocerySheet(context, userId, inFridge: true),
        ),
        const SizedBox(height: 12),
        if (fridgeList.isEmpty)
          LifeOsSoftCard(
            child: Column(
              children: [
                Icon(Icons.ac_unit_rounded, size: 38, color: c.primary),
                const SizedBox(height: 8),
                Text(
                  'Chưa ghi nhận thực phẩm cần canh hạn dùng',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lưu thịt cá, rau xanh, sữa thanh trùng mới mua để LifeOS nhắc chế biến trước khi quá hạn.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                ),
              ],
            ),
          )
        else
          ...fridgeList.map((item) {
            final daysLeft = item.daysFreshRemaining(now) ?? 4;
            final urgent = daysLeft <= 2;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LifeOsSoftCard(
                padding: const EdgeInsets.all(13),
                child: Row(
                  children: [
                    LifeOsIconSquircle(
                      icon: Icons.kitchen_outlined,
                      tone: urgent
                          ? LifeOsAccentTone.coral
                          : LifeOsAccentTone.blue,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            '${item.quantityLabel} · ${item.aisle.label}',
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    LifeOsStatusPill(
                      label: daysLeft <= 0
                          ? 'Nấu ngay hôm nay!'
                          : 'Còn $daysLeft ngày tươi',
                      tone: urgent
                          ? LifeOsAccentTone.coral
                          : LifeOsAccentTone.emerald,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Đã đem ra nấu',
                      onPressed: () => context.read<DailyLifeBloc>().add(
                        GroceryItemDeleted(userId: userId, itemId: item.id),
                      ),
                      icon: Icon(
                        Icons.check_circle_outline_rounded,
                        size: 20,
                        color: c.primary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _showAddGrocerySheet(
    BuildContext context,
    String userId, {
    required bool inFridge,
  }) async {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '500g');
    final priceCtrl = TextEditingController(text: '55000');
    var aisle = GroceryAisle.produce;
    var freshDays = 4;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModal) => Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  inFridge
                      ? 'Cất thực phẩm vào Tủ lạnh'
                      : 'Thêm món vào Giỏ đi chợ',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên thực phẩm / Đồ dùng',
                    hintText: 'VD: Cá hồi Na Uy, Súp lơ xanh...',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Định lượng',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Giá dự kiến (₫)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<GroceryAisle>(
                  isExpanded: true,
                  initialValue: aisle,
                  decoration: const InputDecoration(
                    labelText: 'Quầy hàng / Nhóm',
                  ),
                  items: GroceryAisle.values
                      .map(
                        (a) => DropdownMenuItem(value: a, child: Text(a.label)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setModal(() => aisle = v);
                  },
                ),
                if (inFridge) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: freshDays,
                    decoration: const InputDecoration(
                      labelText: 'Số ngày bảo quản tươi',
                    ),
                    items: const [2, 3, 4, 7, 14, 30]
                        .map(
                          (d) => DropdownMenuItem(
                            value: d,
                            child: Text('Dùng trong $d ngày'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setModal(() => freshDays = v);
                    },
                  ),
                ],
                const SizedBox(height: 14),
                LifeOsPrimaryCtaButton(
                  label: inFridge ? 'Lưu vào Tủ lạnh' : 'Thêm vào Giỏ đi chợ',
                  icon: Icons.check_rounded,
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    context.read<DailyLifeBloc>().add(
                      GroceryItemAdded(
                        userId: userId,
                        name: name,
                        quantityLabel: qtyCtrl.text.trim(),
                        aisle: aisle,
                        estimatedMinor:
                            int.tryParse(priceCtrl.text.trim()) ?? 0,
                        inFridgeStorage: inFridge,
                        expiryDate: inFridge
                            ? DateTime.now().add(Duration(days: freshDays))
                            : null,
                      ),
                    );
                    Navigator.of(sheetCtx).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MealSlotLine extends StatelessWidget {
  final String slot;
  final String dish;

  const _MealSlotLine({required this.slot, required this.dish});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
          decoration: BoxDecoration(
            color: c.primarySubtle,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            slot,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: c.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            dish,
            style: TextStyle(
              fontSize: 13.2,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
