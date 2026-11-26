import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/privacy_mask_formatter.dart';
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
import '../widgets/subscription_intelligence_banner.dart';

/// Tracks recurring subscription drains and appliance warranties.
class SubscriptionsWarrantyPage extends StatefulWidget {
  const SubscriptionsWarrantyPage({super.key});

  @override
  State<SubscriptionsWarrantyPage> createState() =>
      _SubscriptionsWarrantyPageState();
}

class _SubscriptionsWarrantyPageState extends State<SubscriptionsWarrantyPage> {
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');

  bool _showWarranties = false;
  bool _dueSoonOnly = false;
  String? _selectedWalletId;
  final Set<String> _renewingItemIds = <String>{};
  final LifeOsStableListRegistry _itemEntranceRegistry =
      LifeOsStableListRegistry(animateInitialItems: false);
  final Set<String> _revealedNoteIds = <String>{};

  T? _maybeRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } catch (_) {
      return null;
    }
  }

  R? _maybeSelect<B extends StateStreamable<S>, S, R>(
    BuildContext context,
    R Function(S state) selector,
  ) {
    try {
      return context.select<B, R>((bloc) => selector(bloc.state));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.select((AuthBloc b) => b.state.user?.id);
    if (userId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = TammySemanticColors.of(context);
    final wallets =
        _maybeSelect<
          TransactionListBloc,
          TransactionListState,
          List<WalletEntity>
        >(context, (s) => s.wallets) ??
        const <WalletEntity>[];
    final activeWalletId = wallets.any((w) => w.id == _selectedWalletId)
        ? _selectedWalletId
        : (wallets.isNotEmpty ? wallets.first.id : null);
    final now = DateTime.now();

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
                  title: 'Gói Đăng ký & Bảo hành',
                  showBackButton: true,
                  trailingAction: IconButton.filledTonal(
                    tooltip: 'Thêm gói hoặc bảo hành',
                    onPressed: () => _showSaveDialog(
                      context,
                      userId,
                      defaultWarranty: _showWarranties,
                    ),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ),
                Expanded(
                  child: BlocBuilder<ProUtilitiesBloc, ProUtilitiesState>(
                    buildWhen: (p, n) =>
                        p.isLoading != n.isLoading ||
                        p.subscriptionsAndWarranties !=
                            n.subscriptionsAndWarranties,
                    builder: (context, state) {
                      final dueSoonCount = state.subscriptionsAndWarranties
                          .where((e) => e.isDueSoon(now))
                          .length;
                      final baseVisible = _showWarranties
                          ? state.warrantiesOnly
                          : state.subscriptionsOnly;
                      final visible = _dueSoonOnly
                          ? baseVisible.where((e) => e.isDueSoon(now)).toList()
                          : baseVisible;
                      final newlyAddedIds =
                          state.isLoading &&
                              state.subscriptionsAndWarranties.isEmpty
                          ? const <String>{}
                          : _itemEntranceRegistry.registerSnapshot(
                              visible.map((e) => e.id),
                            );
                      var nextStaggerIndex = 0;

                      return Center(
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
                              // 1. Annual & Monthly Burn Radar Hero Card
                              LifeOsMintHeroCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const BananaGlassIcon(
                                                assetPath: AppAssets
                                                    .icToolSubscription,
                                                fallbackIcon:
                                                    Icons.radar_rounded,
                                                size: 30,
                                                borderRadius: 9,
                                              ),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  'Radar Chi phí Thuê bao Tự động',
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
                                          LifeOsAnimatedStatusBadge(
                                            statusKey:
                                                'subs_due_soon_$dueSoonCount',
                                            icon: Icons
                                                .notifications_active_outlined,
                                            label: '$dueSoonCount sắp đến hạn',
                                            tone: dueSoonCount > 0
                                                ? LifeOsAccentTone.amber
                                                : LifeOsAccentTone.emerald,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    IntrinsicHeight(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Chi phí ngầm / tháng',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: LifeOsTruthfulNumericText(
                                                    formattedValue:
                                                        VndAmount.format(
                                                          state
                                                              .totalMonthlySubBurnMinor,
                                                        ),
                                                    style: TextStyle(
                                                      fontSize: 19,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: c.textPrimary,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                    ),
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
                                                  'Tổng phí / năm',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: LifeOsTruthfulNumericText(
                                                    formattedValue:
                                                        VndAmount.format(
                                                          state
                                                              .totalAnnualSubBurnMinor,
                                                        ),
                                                    style: TextStyle(
                                                      fontSize: 19,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: c.error,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
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
                              if (!_showWarranties)
                                Builder(
                                  builder: (bannerCtx) {
                                    final recentTransactions =
                                        _maybeSelect<
                                          TransactionListBloc,
                                          TransactionListState,
                                          List<TransactionEntity>
                                        >(
                                          bannerCtx,
                                          (s) => s.allTransactions,
                                        ) ??
                                        const <TransactionEntity>[];
                                    return SubscriptionIntelligenceBanner(
                                      subscriptions: state.subscriptionsOnly,
                                      recentTransactions: recentTransactions,
                                      referenceNow: now,
                                    );
                                  },
                                ),

                              // 2. Segmented Toggle: Subscriptions vs Appliance Warranties
                              LifeOsSegmentedPills<bool>(
                                selected: _showWarranties,
                                options: const [
                                  (
                                    false,
                                    'Gói đăng ký',
                                    Icons.autorenew_rounded,
                                  ),
                                  (
                                    true,
                                    'Phiếu bảo hành',
                                    Icons.verified_user_outlined,
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _showWarranties = v),
                              ),
                              if (baseVisible.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    ChoiceChip(
                                      key: const Key('subs_filter_all'),
                                      label: Text(
                                        'Tất cả (${baseVisible.length})',
                                      ),
                                      selected: !_dueSoonOnly,
                                      onSelected: (_) =>
                                          setState(() => _dueSoonOnly = false),
                                    ),
                                    ChoiceChip(
                                      key: const Key('subs_filter_due_soon'),
                                      label: Text(
                                        'Sắp đến hạn (${baseVisible.where((e) => e.isDueSoon(now)).length})',
                                      ),
                                      selected: _dueSoonOnly,
                                      onSelected: (sel) =>
                                          setState(() => _dueSoonOnly = sel),
                                    ),
                                  ],
                                ),
                              ],
                              if (!_showWarranties && wallets.length > 1) ...[
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: activeWalletId,
                                  decoration: const InputDecoration(
                                    labelText: 'Ví ghi nhận gia hạn mặc định',
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
                                                fontFeatures: [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _selectedWalletId = v),
                                ),
                              ],
                              const SizedBox(height: 12),

                              // 3. Active Items List
                              if (visible.isEmpty)
                                LifeOsSoftCard(
                                  child: Column(
                                    children: [
                                      BananaGlassIcon(
                                        assetPath: _showWarranties
                                            ? AppAssets.icSysShield
                                            : AppAssets.icToolSubscription,
                                        fallbackIcon: _dueSoonOnly
                                            ? Icons.check_circle_outline_rounded
                                            : (_showWarranties
                                                  ? Icons.verified_user_outlined
                                                  : Icons
                                                        .subscriptions_outlined),
                                        size: 48,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        _dueSoonOnly && baseVisible.isNotEmpty
                                            ? 'Không có mục nào sắp đến hạn'
                                            : (_showWarranties
                                                  ? 'Chưa có phiếu bảo hành thiết bị nào'
                                                  : 'Chưa có gói đăng ký tự động nào'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _dueSoonOnly && baseVisible.isNotEmpty
                                            ? 'Tất cả gói và bảo hành đều đang còn hạn an toàn.'
                                            : (_showWarranties
                                                  ? 'Bấm nút "+" góc trên để lưu phiếu bảo hành thiết bị.'
                                                  : 'Bấm nút "+" góc trên để thêm gói đăng ký định kỳ.'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                      if (_dueSoonOnly &&
                                          baseVisible.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        FilledButton.tonalIcon(
                                          key: const Key(
                                            'subs_reset_filter_btn',
                                          ),
                                          onPressed: () => setState(
                                            () => _dueSoonOnly = false,
                                          ),
                                          icon: const Icon(
                                            Icons.filter_alt_off_rounded,
                                            size: 17,
                                          ),
                                          label: const Text('Xem tất cả'),
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              else
                                ...visible.map((item) {
                                  final daysLeft = item.daysRemainingFrom(now);
                                  final dueSoon = item.isDueSoon(now);
                                  final note = item.serialOrNote.trim();
                                  final hasSensitiveNote = note.isNotEmpty;
                                  final isNoteRevealed = _revealedNoteIds
                                      .contains(item.id);
                                  final isRenewing = _renewingItemIds.contains(
                                    item.id,
                                  );
                                  final animateItem = newlyAddedIds.contains(
                                    item.id,
                                  );
                                  final staggerIndex = animateItem
                                      ? nextStaggerIndex++
                                      : 0;
                                  return Padding(
                                    key: ValueKey<String>(item.id),
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: LifeOsAnimatedItemEntrance(
                                      key: ValueKey<String>(
                                        'sub_entrance_${item.id}',
                                      ),
                                      itemId: item.id,
                                      animateOnMount: animateItem,
                                      staggerIndex: staggerIndex,
                                      child: LifeOsSoftCard(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                BananaGlassIcon(
                                                  assetPath: item.isWarranty
                                                      ? AppAssets.icSysShield
                                                      : AppAssets
                                                            .icToolSubscription,
                                                  fallbackIcon: item.isWarranty
                                                      ? Icons.shield_outlined
                                                      : Icons.autorenew_rounded,
                                                  size: 42,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        item.title,
                                                        softWrap: true,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 15,
                                                          color: c.textPrimary,
                                                        ),
                                                      ),
                                                      Text(
                                                        '${item.providerOrStore.isEmpty ? item.cycle.labelVi : "${item.providerOrStore} · ${item.cycle.labelVi}"} · Hạn: ${_dateFmt.format(item.nextBillingOrExpiryDate)}',
                                                        softWrap: true,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              c.textSecondary,
                                                          fontFeatures: const [
                                                            FontFeature.tabularFigures(),
                                                          ],
                                                        ),
                                                      ),
                                                      if (hasSensitiveNote)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 3,
                                                              ),
                                                          child: Text(
                                                            isNoteRevealed
                                                                ? 'Ghi chú / Serial: $note'
                                                                : 'Ghi chú / Serial: ${PrivacyMaskFormatter.maskNotePreview(note)}',
                                                            softWrap: true,
                                                            style: TextStyle(
                                                              fontSize: 11.8,
                                                              color: c
                                                                  .textSecondary,
                                                              fontFeatures: const [
                                                                FontFeature.tabularFigures(),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                if (!item.isWarranty) ...[
                                                  const SizedBox(width: 8),
                                                  ConstrainedBox(
                                                    constraints:
                                                        const BoxConstraints(
                                                          maxWidth: 118,
                                                        ),
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: Text(
                                                        VndAmount.format(
                                                          item.amountMinor,
                                                        ),
                                                        style: TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: c.textPrimary,
                                                          fontFeatures: const [
                                                            FontFeature.tabularFigures(),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            SizedBox(
                                              width: double.infinity,
                                              child: Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                alignment:
                                                    WrapAlignment.spaceBetween,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  LifeOsStatusPill(
                                                    icon: daysLeft < 0
                                                        ? Icons
                                                              .error_outline_rounded
                                                        : Icons
                                                              .schedule_rounded,
                                                    label: daysLeft < 0
                                                        ? 'Đã quá hạn ${daysLeft.abs()} ngày'
                                                        : 'Còn $daysLeft ngày',
                                                    tone: daysLeft < 0
                                                        ? LifeOsAccentTone.coral
                                                        : dueSoon
                                                        ? LifeOsAccentTone.amber
                                                        : LifeOsAccentTone
                                                              .emerald,
                                                  ),
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (!item.isWarranty)
                                                        TextButton.icon(
                                                          key: Key(
                                                            'renew_sub_wallet_${item.id}',
                                                          ),
                                                          style:
                                                              TextButton.styleFrom(
                                                                visualDensity:
                                                                    VisualDensity
                                                                        .compact,
                                                              ),
                                                          onPressed: isRenewing
                                                              ? null
                                                              : () => _renewAndRecordToWallet(
                                                                  context,
                                                                  userId:
                                                                      userId,
                                                                  item: item,
                                                                  wallets:
                                                                      wallets,
                                                                  activeWalletId:
                                                                      activeWalletId,
                                                                ),
                                                          icon: isRenewing
                                                              ? const SizedBox(
                                                                  width: 14,
                                                                  height: 14,
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                                )
                                                              : const Icon(
                                                                  Icons
                                                                      .payments_outlined,
                                                                  size: 16,
                                                                ),
                                                          label: const Text(
                                                            'Ghi vào Ví',
                                                          ),
                                                        ),
                                                      if (hasSensitiveNote)
                                                        IconButton(
                                                          key: Key(
                                                            'toggle_sub_note_${item.id}',
                                                          ),
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          tooltip:
                                                              isNoteRevealed
                                                              ? 'Ẩn ghi chú / serial'
                                                              : 'Hiện ghi chú / serial',
                                                          onPressed: () => setState(
                                                            () {
                                                              if (isNoteRevealed) {
                                                                _revealedNoteIds
                                                                    .remove(
                                                                      item.id,
                                                                    );
                                                              } else {
                                                                _revealedNoteIds
                                                                    .add(
                                                                      item.id,
                                                                    );
                                                              }
                                                            },
                                                          ),
                                                          icon: Icon(
                                                            isNoteRevealed
                                                                ? Icons
                                                                      .visibility_off_outlined
                                                                : Icons
                                                                      .visibility_outlined,
                                                            size: 19,
                                                            color:
                                                                c.textSecondary,
                                                          ),
                                                        ),
                                                      IconButton(
                                                        key: Key(
                                                          'edit_sub_${item.id}',
                                                        ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        tooltip: 'Sửa mục',
                                                        onPressed: () =>
                                                            _showSaveDialog(
                                                              context,
                                                              userId,
                                                              existing: item,
                                                            ),
                                                        icon: Icon(
                                                          Icons.edit_outlined,
                                                          size: 19,
                                                          color:
                                                              c.textSecondary,
                                                        ),
                                                      ),
                                                      IconButton(
                                                        key: Key(
                                                          'delete_sub_${item.id}',
                                                        ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        tooltip: 'Xóa',
                                                        onPressed: () async {
                                                          final confirmed =
                                                              await showDestructiveConfirmDialog(
                                                                context:
                                                                    context,
                                                                title:
                                                                    'Xóa "${item.title}"?',
                                                                message:
                                                                    'Mục theo dõi này sẽ bị xóa khỏi Radar và không còn nhắc hạn gia hạn.',
                                                                confirmLabel:
                                                                    'Xóa',
                                                              );
                                                          if (!confirmed ||
                                                              !context
                                                                  .mounted) {
                                                            return;
                                                          }
                                                          _revealedNoteIds
                                                              .remove(item.id);
                                                          context
                                                              .read<
                                                                ProUtilitiesBloc
                                                              >()
                                                              .add(
                                                                SubscriptionOrWarrantyDeleted(
                                                                  userId:
                                                                      userId,
                                                                  itemId:
                                                                      item.id,
                                                                ),
                                                              );
                                                        },
                                                        icon: Icon(
                                                          Icons
                                                              .delete_outline_rounded,
                                                          size: 19,
                                                          color:
                                                              c.textSecondary,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),

                              const SizedBox(height: 14),
                              LifeOsPrimaryCtaButton(
                                icon: Icons.add_rounded,
                                label: _showWarranties
                                    ? 'Thêm phiếu bảo hành thiết bị'
                                    : 'Thêm gói đăng ký theo dõi',
                                onPressed: () => _showSaveDialog(
                                  context,
                                  userId,
                                  defaultWarranty: _showWarranties,
                                ),
                              ),
                            ],
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

  Future<void> _renewAndRecordToWallet(
    BuildContext context, {
    required String userId,
    required SubscriptionWarrantyEntity item,
    required List<WalletEntity> wallets,
    required String? activeWalletId,
  }) async {
    if (wallets.isEmpty || activeWalletId == null) {
      LifeOsTopToast.show(
        context,
        'Chưa có ví thanh toán. Hãy tạo ví ở tab Tài chính trước khi ghi gia hạn.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }
    final txActionBloc = _maybeRead<TransactionActionBloc>(context);
    if (txActionBloc == null) {
      LifeOsTopToast.show(
        context,
        'Không thể kết nối sổ giao dịch ví cá nhân.',
        kind: LifeOsToastKind.error,
      );
      return;
    }

    setState(() => _renewingItemIds.add(item.id));
    final res = await txActionBloc.submitAndAwaitCreate(
      TransactionCreateSubmitted(
        operationId: const Uuid().v4(),
        userId: userId,
        walletId: activeWalletId,
        categoryName: 'Giải trí & Đăng ký',
        kind: TransactionKind.expense,
        amountMinor: item.amountMinor,
        merchant: item.title,
        note: 'Gia hạn gói ${item.cycle.labelVi}',
        occurredAt: DateTime.now(),
      ),
    );
    if (!context.mounted) return;
    setState(() => _renewingItemIds.remove(item.id));

    if (res.status != ActionStatus.success) {
      LifeOsTopToast.show(
        context,
        res.failure?.message ?? 'Không thể ghi giao dịch gia hạn vào Ví.',
        kind: LifeOsToastKind.error,
      );
      return;
    }

    final nextDate = item.computeNextRenewalDate();
    context.read<ProUtilitiesBloc>().add(
      SubscriptionOrWarrantySaved(
        userId: userId,
        itemId: item.id,
        title: item.title,
        providerOrStore: item.providerOrStore,
        cycle: item.cycle,
        amountMinor: item.amountMinor,
        nextBillingOrExpiryDate: nextDate,
        serialOrNote: item.serialOrNote,
      ),
    );
    LifeOsTopToast.show(
      context,
      'Đã ghi gia hạn "${item.title}" vào Ví và dời hạn tới ${_dateFmt.format(nextDate)}.',
      kind: LifeOsToastKind.success,
    );
  }

  Future<void> _showSaveDialog(
    BuildContext context,
    String userId, {
    SubscriptionWarrantyEntity? existing,
    bool defaultWarranty = false,
  }) async {
    final bloc = context.read<ProUtilitiesBloc>();
    await showDialog<void>(
      context: context,
      builder: (_) => _SaveSubscriptionWarrantyDialog(
        bloc: bloc,
        userId: userId,
        existing: existing,
        defaultWarranty: defaultWarranty,
      ),
    );
  }
}

class _SaveSubscriptionWarrantyDialog extends StatefulWidget {
  const _SaveSubscriptionWarrantyDialog({
    required this.bloc,
    required this.userId,
    this.existing,
    this.defaultWarranty = false,
  });

  final ProUtilitiesBloc bloc;
  final String userId;
  final SubscriptionWarrantyEntity? existing;
  final bool defaultWarranty;

  @override
  State<_SaveSubscriptionWarrantyDialog> createState() =>
      _SaveSubscriptionWarrantyDialogState();
}

class _SaveSubscriptionWarrantyDialogState
    extends State<_SaveSubscriptionWarrantyDialog> {
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');

  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late final TextEditingController _providerCtrl = TextEditingController(
    text: widget.existing?.providerOrStore ?? '',
  );
  late final TextEditingController _amountCtrl = TextEditingController(
    text: widget.existing != null
        ? '${widget.existing!.amountMinor}'
        : (widget.defaultWarranty ? '0' : '120000'),
  );
  late final TextEditingController _noteCtrl = TextEditingController(
    text: widget.existing?.serialOrNote ?? '',
  );
  late SubscriptionCycle _cycle =
      widget.existing?.cycle ??
      (widget.defaultWarranty
          ? SubscriptionCycle.warrantyOnly
          : SubscriptionCycle.monthly);
  late DateTime _targetDate =
      widget.existing?.nextBillingOrExpiryDate ??
      DateTime.now().add(Duration(days: widget.defaultWarranty ? 365 : 30));

  @override
  void dispose() {
    _titleCtrl.dispose();
    _providerCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isEdit = existing != null;
    return AlertDialog(
      title: Text(
        isEdit
            ? (_cycle == SubscriptionCycle.warrantyOnly
                  ? 'Sửa Phiếu Bảo hành'
                  : 'Sửa Gói Đăng ký')
            : (_cycle == SubscriptionCycle.warrantyOnly
                  ? 'Thêm Phiếu Bảo hành'
                  : 'Thêm Gói Đăng ký Tự động'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<SubscriptionCycle>(
              isExpanded: true,
              initialValue: _cycle,
              decoration: const InputDecoration(labelText: 'Loại chu kỳ'),
              items: SubscriptionCycle.values
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(e.labelVi),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _cycle = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('sub_title_input'),
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên dịch vụ / Thiết bị',
                hintText: 'VD: Spotify / Tủ lạnh Samsung',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _providerCtrl,
              decoration: const InputDecoration(
                labelText: 'Nhà cung cấp / Nơi mua',
              ),
            ),
            if (_cycle != SubscriptionCycle.warrantyOnly) ...[
              const SizedBox(height: 10),
              TextField(
                key: const Key('sub_amount_input'),
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số tiền mỗi kỳ (VND)',
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Số Serial / Ghi chú hủy gia hạn',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _targetDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2040),
                );
                if (picked != null && mounted) {
                  setState(() => _targetDate = picked);
                }
              },
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(
                'Ngày gia hạn / hết hạn: ${_dateFmt.format(_targetDate)}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('submit_sub_button'),
          onPressed: () {
            final title = _titleCtrl.text.trim();
            final amt = _cycle == SubscriptionCycle.warrantyOnly
                ? 0
                : (VndAmount.tryParseInput(_amountCtrl.text) ?? 0);
            if (title.isEmpty ||
                (_cycle != SubscriptionCycle.warrantyOnly && amt <= 0)) {
              LifeOsTopToast.show(
                context,
                _cycle == SubscriptionCycle.warrantyOnly
                    ? 'Vui lòng nhập tên thiết bị cần bảo hành.'
                    : 'Vui lòng nhập tên gói và số tiền hợp lệ (> 0 ₫).',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            widget.bloc.add(
              SubscriptionOrWarrantySaved(
                userId: widget.userId,
                itemId: existing?.id,
                title: title,
                providerOrStore: _providerCtrl.text.trim(),
                cycle: _cycle,
                amountMinor: amt,
                nextBillingOrExpiryDate: _targetDate,
                serialOrNote: _noteCtrl.text.trim(),
              ),
            );
            Navigator.of(context).pop();
          },
          child: Text(isEdit ? 'Lưu thay đổi' : 'Lưu theo dõi'),
        ),
      ],
    );
  }
}
