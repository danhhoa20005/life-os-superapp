import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../../transactions/presentation/bloc/transaction_state.dart';
import '../../domain/entities/daily_life_entities.dart';
import '../bloc/daily_life_bloc.dart';

class KitchenGroceriesPage extends StatefulWidget {
  const KitchenGroceriesPage({super.key});

  @override
  State<KitchenGroceriesPage> createState() => _KitchenGroceriesPageState();
}

class _KitchenGroceriesPageState extends State<KitchenGroceriesPage> {
  String _tab = 'basket';
  String _basketFilter = 'all'; // 'all' | 'pending' | 'bought'
  int _featuredComboIndex = 0;
  String? _selectedWalletId;
  bool _isSubmittingCheckout = false;

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final userId = user?.id ?? '';
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    final String? resolvedWalletId = wallets.isEmpty
        ? null
        : (_selectedWalletId != null &&
                  wallets.any((w) => w.id == _selectedWalletId)
              ? _selectedWalletId!
              : UserBehaviorPrefs.resolvePreferredWalletId(
                  wallets.map((w) => w.id),
                ));

    return BlocConsumer<DailyLifeBloc, DailyLifeState>(
      listenWhen: (p, n) =>
          (n.failure != null && p.failure != n.failure) ||
          (n.successBanner != null && p.successBanner != n.successBanner),
      listener: (context, state) {
        if (state.failure != null) {
          LifeOsTopToast.show(
            context,
            state.failure!.message,
            kind: LifeOsToastKind.error,
          );
        } else if (state.successBanner != null) {
          LifeOsTopToast.show(context, state.successBanner!);
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
                                                  : 'Quản lý giỏ đi chợ, thực đơn & hạn dùng thực phẩm',
                                              softWrap: true,
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
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
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
                                              ),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  'Cần mua thêm',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        VerticalDivider(
                                          width: 14,
                                          color: c.separator,
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  VndAmount.format(
                                                    snap.pendingGroceriesMinor +
                                                        snap.boughtGroceriesMinor,
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 17,
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
                                                  'Dự toán giỏ chợ',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        VerticalDivider(
                                          width: 14,
                                          color: c.separator,
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
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
                                              ),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  'Trong tủ lạnh',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: c.textSecondary,
                                                  ),
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
                                wallets,
                                resolvedWalletId,
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

  Future<void> _checkoutBoughtGroceries({
    required String userId,
    required List<WalletEntity> wallets,
    required String? selectedWalletId,
    required int boughtMinor,
  }) async {
    if (wallets.isEmpty || selectedWalletId == null) {
      LifeOsTopToast.show(
        context,
        'Vui lòng tạo ít nhất 1 Ví trong tab Tài chính trước khi ghi chi tiêu đi chợ.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }
    if (_isSubmittingCheckout) return;

    final txActionBloc = context.read<TransactionActionBloc>();
    final dailyBloc = context.read<DailyLifeBloc>();
    setState(() => _isSubmittingCheckout = true);

    late final TransactionActionState outcome;
    try {
      outcome = await txActionBloc.submitAndAwaitCreate(
        TransactionCreateSubmitted(
          operationId: 'groc_${DateTime.now().millisecondsSinceEpoch}',
          userId: userId,
          walletId: selectedWalletId,
          categoryId: 'cat_food',
          categoryName: 'Ăn uống',
          kind: TransactionKind.expense,
          amountMinor: boughtMinor,
          merchant: 'Đi chợ & Thực phẩm Bếp gia đình',
          note: 'Chốt từ Giỏ đi chợ thông minh LifeOS',
          occurredAt: DateTime.now(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingCheckout = false);
      }
    }

    if (!mounted) return;
    final createdTx = outcome.lastCreatedTransaction;
    if (outcome.status != ActionStatus.success || createdTx == null) {
      LifeOsTopToast.show(
        context,
        outcome.failure?.message ??
            'Không thể ghi chi tiêu đi chợ — vui lòng thử lại.',
        kind: LifeOsToastKind.error,
      );
      return;
    }

    await UserBehaviorPrefs.rememberWallet(selectedWalletId);
    dailyBloc.add(BoughtGroceriesCleared(userId, suppressSuccessBanner: true));
    if (!mounted) return;

    final confirmedTxId = createdTx.id;
    LifeOsTopToast.show(
      context,
      'Đã ghi chi tiêu đi chợ (${VndAmount.format(boughtMinor)}) vào Ví.',
      actionLabel: 'Hoàn tác',
      onAction: () {
        txActionBloc.add(
          TransactionReverseRequested(
            userId: userId,
            transactionId: confirmedTxId,
            reason: 'Hoàn tác chi tiêu đi chợ',
          ),
        );
        if (mounted) {
          LifeOsTopToast.show(
            context,
            'Đã hoàn tác khoản chi đi chợ.',
            kind: LifeOsToastKind.info,
          );
        }
      },
    );
  }

  Widget _buildBasketTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    List<WalletEntity> wallets,
    String? resolvedWalletId,
    List<SmartGroceryItemEntity> shoppingList,
    int boughtMinor,
  ) {
    final pendingCount = shoppingList.where((g) => !g.isBought).length;
    final boughtCount = shoppingList.where((g) => g.isBought).length;
    final visibleList = shoppingList.where((g) {
      if (_basketFilter == 'pending') return !g.isBought;
      if (_basketFilter == 'bought') return g.isBought;
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('open_add_grocery_btn'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                onPressed: userId.isEmpty
                    ? null
                    : () => _showAddGrocerySheet(
                        context,
                        userId,
                        inFridge: false,
                      ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Thêm món tự chọn'),
                ),
              ),
            ),
            if (boughtMinor > 0) ...[
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('checkout_grocery_to_wallet_btn'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  onPressed: userId.isEmpty || _isSubmittingCheckout
                      ? null
                      : () => _checkoutBoughtGroceries(
                          userId: userId,
                          wallets: wallets,
                          selectedWalletId: resolvedWalletId,
                          boughtMinor: boughtMinor,
                        ),
                  icon: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                  ),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Ghi Ví ${VndAmount.format(boughtMinor)}',
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (boughtMinor > 0 && wallets.length > 1) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const Key('grocery_wallet_selector'),
            isExpanded: true,
            initialValue: resolvedWalletId,
            decoration: const InputDecoration(
              labelText: 'Chọn Ví thanh toán đi chợ',
              isDense: true,
            ),
            items: wallets
                .map(
                  (w) => DropdownMenuItem(
                    value: w.id,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${w.name} (${VndAmount.format(w.balanceMinor)})',
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedWalletId = v);
            },
          ),
        ],
        if (shoppingList.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                key: const Key('grocery_filter_all'),
                label: Text('Tất cả (${shoppingList.length})'),
                selected: _basketFilter == 'all',
                onSelected: (_) => setState(() => _basketFilter = 'all'),
              ),
              ChoiceChip(
                key: const Key('grocery_filter_pending'),
                label: Text('Cần mua ($pendingCount)'),
                selected: _basketFilter == 'pending',
                onSelected: (sel) =>
                    setState(() => _basketFilter = sel ? 'pending' : 'all'),
              ),
              ChoiceChip(
                key: const Key('grocery_filter_bought'),
                label: Text('Đã mua ($boughtCount)'),
                selected: _basketFilter == 'bought',
                onSelected: (sel) =>
                    setState(() => _basketFilter = sel ? 'bought' : 'all'),
              ),
            ],
          ),
        ],
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
                  'Thêm món cần mua hoặc chọn từ tab "Ăn gì hôm nay".',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                ),
              ],
            ),
          )
        else if (visibleList.isEmpty)
          LifeOsSoftCard(
            child: Column(
              children: [
                Icon(Icons.filter_list_off_rounded, size: 36, color: c.primary),
                const SizedBox(height: 8),
                Text(
                  _basketFilter == 'pending'
                      ? 'Bạn đã mua đủ tất cả các món trong giỏ!'
                      : 'Chưa có món nào được đánh dấu đã mua',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  key: const Key('grocery_reset_filter_btn'),
                  onPressed: () => setState(() => _basketFilter = 'all'),
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: const Text('Xem tất cả'),
                ),
              ],
            ),
          )
        else
          ...visibleList.map((item) {
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: item.isBought,
                          onChanged: (_) => context.read<DailyLifeBloc>().add(
                            GroceryItemBoughtToggled(
                              userId: userId,
                              item: item,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                softWrap: true,
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
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
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
                          tooltip: 'Xóa món',
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
                    Padding(
                      padding: const EdgeInsets.only(left: 40, top: 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Tooltip(
                            message:
                                'Chuyển món này vào Tủ lạnh theo dõi hạn dùng',
                            child: Material(
                              color: const Color(
                                0xFF0EA5E9,
                              ).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                key: Key('move_grocery_to_fridge_${item.id}'),
                                borderRadius: BorderRadius.circular(20),
                                onTap: userId.isEmpty
                                    ? null
                                    : () => context.read<DailyLifeBloc>().add(
                                        GroceryMovedToFridge(
                                          userId: userId,
                                          item: item,
                                        ),
                                      ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.kitchen_outlined,
                                        size: 14.5,
                                        color: Color(0xFF0284C7),
                                      ),
                                      SizedBox(width: 5),
                                      Text(
                                        'Cất vào Tủ lạnh',
                                        style: TextStyle(
                                          fontSize: 11.8,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0284C7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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
                    icon: Icons.restaurant_rounded,
                    bananaAsset: AppAssets.icCatFood,
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
          'Thực đơn theo bữa (${combos.length})',
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
                          softWrap: true,
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
                  'Lưu thực phẩm tươi sống để theo dõi hạn bảo quản.',
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
