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
import '../../../budgets/domain/entities/budget_entities.dart';
import '../../../budgets/domain/usecases/budget_usecases.dart';
import '../../../budgets/presentation/bloc/budget_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../bloc/family_bloc.dart';

/// Screen 08: "Quỹ gia đình" following Unified LifeOS Design System v3.19.
class FamilyFundsPage extends StatelessWidget {
  const FamilyFundsPage({super.key});

  T? _maybeRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } catch (_) {
      return null;
    }
  }

  SemanticStatusKind _expenseBadgeKind(FundExpenseStatus status) =>
      switch (status) {
        FundExpenseStatus.draft => SemanticStatusKind.info,
        FundExpenseStatus.pendingApproval => SemanticStatusKind.provisional,
        FundExpenseStatus.approved => SemanticStatusKind.info,
        FundExpenseStatus.executed => SemanticStatusKind.success,
        FundExpenseStatus.reconciled => SemanticStatusKind.success,
        FundExpenseStatus.rejected => SemanticStatusKind.error,
        FundExpenseStatus.cancelled => SemanticStatusKind.warning,
        FundExpenseStatus.disputed => SemanticStatusKind.error,
        FundExpenseStatus.reversed => SemanticStatusKind.warning,
      };

  ({String asset, IconData icon, LifeOsAccentTone tone}) _resolveFundVisual(
    String fundName,
  ) {
    final folded = VietnameseSearchMatcher.fold(fundName);
    if (folded.contains('du lich') ||
        folded.contains('travel') ||
        folded.contains('da lat') ||
        folded.contains('bien') ||
        folded.contains('nghi duong') ||
        folded.contains('chuyen di')) {
      return (
        asset: AppAssets.icLifeSocialTravel,
        icon: Icons.luggage_outlined,
        tone: LifeOsAccentTone.blue,
      );
    }
    if (folded.contains('khan cap') ||
        folded.contains('suc khoe') ||
        folded.contains('y te') ||
        folded.contains('benh') ||
        folded.contains('thuoc') ||
        folded.contains('bao hiem')) {
      return (
        asset: AppAssets.icCatHealth,
        icon: Icons.health_and_safety_outlined,
        tone: LifeOsAccentTone.coral,
      );
    }
    if (folded.contains('xe') ||
        folded.contains('o to') ||
        folded.contains('oto') ||
        folded.contains('bao duong')) {
      return (
        asset: AppAssets.icCatVehicle,
        icon: Icons.directions_car_outlined,
        tone: LifeOsAccentTone.amber,
      );
    }
    if (folded.contains('nha') ||
        folded.contains('chung cu') ||
        folded.contains('can ho') ||
        folded.contains('noi that')) {
      return (
        asset: AppAssets.icCatHousing,
        icon: Icons.home_work_outlined,
        tone: LifeOsAccentTone.purple,
      );
    }
    return (
      asset: AppAssets.icCatIncome,
      icon: Icons.savings_outlined,
      tone: LifeOsAccentTone.emerald,
    );
  }

  static final DateFormat _dtFmt = DateFormat('dd/MM, HH:mm');

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = TammySemanticColors.of(context);
    final family = context.select((FamilyBloc b) => b.state.activeFamily);
    final hasTxBloc = _maybeRead<TransactionListBloc>(context) != null;
    final wallets = hasTxBloc
        ? context.select((TransactionListBloc b) => b.state.wallets)
        : const <WalletEntity>[];
    final dtFmt = _dtFmt;
    final now = DateTime.now();

    return BlocListener<BudgetBloc, BudgetState>(
      listenWhen: (p, n) =>
          (n.failure != null && p.failure != n.failure) ||
          (n.actionMessage != null && p.actionMessage != n.actionMessage),
      listener: (context, state) {
        if (state.failure != null) {
          LifeOsTopToast.show(
            context,
            state.failure!.message,
            kind: LifeOsToastKind.error,
          );
        } else if (state.actionMessage != null) {
          LifeOsTopToast.show(
            context,
            state.actionMessage!,
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
                  title: 'Quỹ gia đình',
                  showBackButton: true,
                  trailingAction: IconButton.filledTonal(
                    tooltip: 'Tạo mục tiêu quỹ mới',
                    onPressed: () => _showCreateFundDialog(
                      context,
                      userId: user.id,
                      familyId: family?.id,
                    ),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ),
                Expanded(
                  child: BlocBuilder<BudgetBloc, BudgetState>(
                    builder: (context, state) {
                      final funds = state.funds;
                      final totalBalance = funds.fold<int>(
                        0,
                        (s, f) => s + f.balanceMinor,
                      );
                      final totalTarget = funds.fold<int>(
                        0,
                        (s, f) => s + f.targetAmountMinor,
                      );

                      final allContributions =
                          <({FundEntity fund, FundContributionEntity item})>[
                            for (final f in funds)
                              for (final contrib in f.recentContributions)
                                (fund: f, item: contrib),
                          ]..sort(
                            (a, b) =>
                                b.item.createdAt.compareTo(a.item.createdAt),
                          );

                      final totalIn = allContributions
                          .where(
                            (e) =>
                                e.item.createdAt.year == now.year &&
                                e.item.createdAt.month == now.month,
                          )
                          .fold<int>(0, (s, e) => s + e.item.amountMinor);

                      final allExpenseRequests =
                          <({FundEntity fund, FundExpenseRequestEntity item})>[
                            for (final f in funds)
                              for (final req in f.expenseRequests)
                                (fund: f, item: req),
                          ]..sort(
                            (a, b) =>
                                b.item.createdAt.compareTo(a.item.createdAt),
                          );

                      final totalOut = allExpenseRequests
                          .where(
                            (e) =>
                                e.item.status.affectsBalance &&
                                e.item.createdAt.year == now.year &&
                                e.item.createdAt.month == now.month,
                          )
                          .fold<int>(0, (s, e) => s + e.item.amountMinor);

                      final pendingExpenses = allExpenseRequests
                          .where(
                            (e) =>
                                e.item.status == FundExpenseStatus.draft ||
                                e.item.status ==
                                    FundExpenseStatus.pendingApproval ||
                                e.item.status == FundExpenseStatus.approved ||
                                e.item.status == FundExpenseStatus.disputed,
                          )
                          .toList();
                      final decidedExpenses = allExpenseRequests
                          .where(
                            (e) =>
                                e.item.status == FundExpenseStatus.executed ||
                                e.item.status == FundExpenseStatus.reconciled ||
                                e.item.status == FundExpenseStatus.rejected ||
                                e.item.status == FundExpenseStatus.cancelled ||
                                e.item.status == FundExpenseStatus.reversed,
                          )
                          .toList();

                      final hasTargetGoal = funds.isNotEmpty && totalTarget > 0;
                      final monthlyPct = hasTargetGoal
                          ? ((totalBalance * 100) / totalTarget)
                                .clamp(0, 100)
                                .round()
                          : 0;
                      final memberNames =
                          family?.members.map((m) => m.fullName).toList() ??
                          <String>[user.fullName];

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
                              // 1. Pastel Mint Hero Card: "Tổng quỹ hiện tại"
                              LifeOsMintHeroCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.start,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const BananaGlassIcon(
                                                  assetPath:
                                                      AppAssets.icCatIncome,
                                                  fallbackIcon:
                                                      Icons.savings_outlined,
                                                  size: 26,
                                                  borderRadius: 8,
                                                ),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    'Tổng quỹ hiện tại',
                                                    softWrap: true,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 14.5,
                                                      color: c.textPrimary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                VndAmount.format(totalBalance),
                                                style: TextStyle(
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: -0.6,
                                                  color: c.textPrimary,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            LifeOsAvatarStack(
                                              names: memberNames,
                                              radius: 15,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${memberNames.length} thành viên',
                                              style: TextStyle(
                                                fontSize: 11.8,
                                                color: c.textSecondary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 22),
                                    IntrinsicHeight(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                const LifeOsIconSquircle(
                                                  icon: Icons
                                                      .arrow_downward_rounded,
                                                  tone:
                                                      LifeOsAccentTone.emerald,
                                                  size: 32,
                                                  iconSize: 16,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          'Tiền vào (Thu)',
                                                          style: TextStyle(
                                                            fontSize: 11.8,
                                                            color:
                                                                c.textSecondary,
                                                          ),
                                                        ),
                                                      ),
                                                      FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          '+${VndAmount.format(totalIn)}',
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: c.primary,
                                                            fontFeatures: const [
                                                              FontFeature.tabularFigures(),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          'Tháng ${now.month}/${now.year}',
                                                          style: TextStyle(
                                                            fontSize: 11.2,
                                                            color:
                                                                c.textSecondary,
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
                                          VerticalDivider(
                                            width: 14,
                                            color: c.separator,
                                          ),
                                          Expanded(
                                            child: Row(
                                              children: [
                                                const LifeOsIconSquircle(
                                                  icon: Icons
                                                      .arrow_upward_rounded,
                                                  tone: LifeOsAccentTone.coral,
                                                  size: 32,
                                                  iconSize: 16,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          'Tiền ra (Chi)',
                                                          style: TextStyle(
                                                            fontSize: 11.8,
                                                            color:
                                                                c.textSecondary,
                                                          ),
                                                        ),
                                                      ),
                                                      FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          '-${VndAmount.format(totalOut)}',
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: c.error,
                                                            fontFeatures: const [
                                                              FontFeature.tabularFigures(),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          'Tháng ${now.month}/${now.year}',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color:
                                                                c.textSecondary,
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
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 2. "Đóng góp tháng này" Progress Card
                              LifeOsSoftCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.groups_outlined,
                                          size: 19,
                                          color: c.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Tiến độ mục tiêu tích lũy',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                        ),
                                        LifeOsStatusPill(
                                          label: '${funds.length} quỹ',
                                          tone: LifeOsAccentTone.emerald,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (funds.isEmpty)
                                      Text(
                                        'Chưa có mục tiêu quỹ nào. Hãy tạo quỹ đầu tiên để theo dõi tiến độ đóng góp cùng gia đình.',
                                        softWrap: true,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: c.textSecondary,
                                        ),
                                      )
                                    else if (!hasTargetGoal) ...[
                                      Text(
                                        VndAmount.format(totalBalance),
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: c.textPrimary,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Các quỹ hiện chưa đặt hạn mức mục tiêu.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ] else ...[
                                      RichText(
                                        text: TextSpan(
                                          children: [
                                            TextSpan(
                                              text: VndAmount.format(
                                                totalBalance,
                                              ),
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                            TextSpan(
                                              text:
                                                  ' / ${VndAmount.format(totalTarget)}',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: c.textSecondary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: LinearProgressIndicator(
                                                minHeight: 9,
                                                value: (monthlyPct / 100).clamp(
                                                  0.0,
                                                  1.0,
                                                ),
                                                backgroundColor:
                                                    c.surfaceRaised,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(c.primary),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Đã đạt $monthlyPct%',
                                            style: TextStyle(
                                              fontSize: 12.5,
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
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              // 3. "Mục tiêu quỹ" Section Header + Cards
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.track_changes_rounded,
                                        size: 19,
                                        color: c.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Mục tiêu quỹ (${funds.length})',
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  TextButton(
                                    onPressed: state.isSaving
                                        ? null
                                        : () => _showCreateFundDialog(
                                            context,
                                            userId: user.id,
                                            familyId: family?.id,
                                          ),
                                    child: const Text('+ Tạo quỹ mới'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              if (funds.isEmpty)
                                LifeOsSoftCard(
                                  child: Column(
                                    children: [
                                      const BananaGlassIcon(
                                        assetPath: AppAssets.icLifeSocialTravel,
                                        fallbackIcon: Icons.luggage_outlined,
                                        size: 48,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Chưa có mục tiêu quỹ nào',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Khởi tạo Quỹ du lịch hè, Quỹ khẩn cấp hoặc Quỹ mua nhà để cả nhà cùng đóng góp và duyệt chi minh bạch.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      FilledButton.icon(
                                        onPressed: state.isSaving
                                            ? null
                                            : () => _showCreateFundDialog(
                                                context,
                                                userId: user.id,
                                                familyId: family?.id,
                                              ),
                                        icon: const Icon(
                                          Icons.add_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('Tạo quỹ đầu tiên'),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ...funds.map((fund) {
                                  final visual = _resolveFundVisual(fund.name);
                                  final pendingCount = fund.expenseRequests
                                      .where(
                                        (r) =>
                                            r.status ==
                                            FundExpenseStatus.pending,
                                      )
                                      .length;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
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
                                                assetPath: visual.asset,
                                                fallbackIcon: visual.icon,
                                                size: 44,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      fund.name,
                                                      softWrap: true,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 15.5,
                                                        color: c.textPrimary,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Wrap(
                                                      spacing: 6,
                                                      runSpacing: 4,
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          fund.scope ==
                                                                  FundScope
                                                                      .family
                                                              ? 'Quỹ chung gia đình'
                                                              : 'Quỹ tích lũy cá nhân',
                                                          style: TextStyle(
                                                            fontSize: 12.2,
                                                            color:
                                                                c.textSecondary,
                                                          ),
                                                        ),
                                                        if (pendingCount > 0)
                                                          LifeOsStatusPill(
                                                            label:
                                                                '$pendingCount chờ duyệt',
                                                            tone:
                                                                LifeOsAccentTone
                                                                    .amber,
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          RichText(
                                            text: TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: VndAmount.format(
                                                    fund.balanceMinor,
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.textPrimary,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                                TextSpan(
                                                  text:
                                                      fund.targetAmountMinor > 0
                                                      ? ' / ${VndAmount.format(fund.targetAmountMinor)}'
                                                      : ' (Chưa đặt mục tiêu)',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: c.textSecondary,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (fund.targetAmountMinor > 0) ...[
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    child: LinearProgressIndicator(
                                                      minHeight: 8,
                                                      value:
                                                          (fund.progressPct /
                                                                  100)
                                                              .clamp(0.0, 1.0),
                                                      backgroundColor:
                                                          c.surfaceRaised,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                            Color
                                                          >(c.primary),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  'Đã đạt ${fund.progressPct}%',
                                                  style: TextStyle(
                                                    fontSize: 12,
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
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              FilledButton.tonalIcon(
                                                key: Key(
                                                  'contribute_fund_btn_${fund.id}',
                                                ),
                                                onPressed: state.isSaving
                                                    ? null
                                                    : () =>
                                                          _showContributeSheet(
                                                            context,
                                                            userId: user.id,
                                                            userName:
                                                                user.fullName,
                                                            fund: fund,
                                                            wallets: wallets,
                                                          ),
                                                icon: const Icon(
                                                  Icons
                                                      .add_circle_outline_rounded,
                                                  size: 17,
                                                ),
                                                label: const Text('Nạp quỹ'),
                                              ),
                                              OutlinedButton.icon(
                                                key: Key(
                                                  'request_fund_expense_btn_${fund.id}',
                                                ),
                                                onPressed: state.isSaving
                                                    ? null
                                                    : () =>
                                                          _showRequestExpenseSheet(
                                                            context,
                                                            userId: user.id,
                                                            userName:
                                                                user.fullName,
                                                            fund: fund,
                                                          ),
                                                icon: const Icon(
                                                  Icons.outbox_rounded,
                                                  size: 17,
                                                ),
                                                label: const Text(
                                                  'Đề xuất chi / Rút quỹ',
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (fund
                                                  .recentContributions
                                                  .isNotEmpty ||
                                              fund
                                                  .expenseRequests
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            LifeOsDetailsDiscloseSection(
                                              label: 'Chi tiết quỹ',
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Lượt nạp gần nhất: ${fund.recentContributions.length} · Yêu cầu chi: ${fund.expenseRequests.length}',
                                                    softWrap: true,
                                                    style: TextStyle(
                                                      fontSize: 12.2,
                                                      color: c.textSecondary,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }),

                              const SizedBox(height: 14),

                              // 4. "Yêu cầu chi quỹ chờ duyệt" Section
                              Row(
                                children: [
                                  Icon(
                                    Icons.pending_actions_rounded,
                                    size: 19,
                                    color: c.warning,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Yêu cầu chi quỹ chờ duyệt (${pendingExpenses.length})',
                                      softWrap: true,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: c.textPrimary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (pendingExpenses.isEmpty)
                                LifeOsSoftCard(
                                  child: Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.verified_outlined,
                                        tone: LifeOsAccentTone.emerald,
                                        size: 38,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Không có yêu cầu chi quỹ nào đang chờ duyệt.',
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ...pendingExpenses.map((entry) {
                                  final fund = entry.fund;
                                  final req = entry.item;
                                  final isFamilyFund =
                                      fund.scope == FundScope.family &&
                                      fund.familyId != null &&
                                      fund.familyId!.isNotEmpty;
                                  final isManager =
                                      isFamilyFund &&
                                      family != null &&
                                      family.id == fund.familyId &&
                                      family.isManager(user.id);
                                  final memberCount =
                                      family?.members.length ?? 1;
                                  final canDecide =
                                      isFamilyFund &&
                                      req.status ==
                                          FundExpenseStatus.pendingApproval &&
                                      FundExpenseStateMachine.canUserDecide(
                                        isManager: isManager,
                                        actorUserId: user.id,
                                        requesterId: req.requesterId,
                                        memberCount: memberCount,
                                      );
                                  final canExecute =
                                      isFamilyFund &&
                                      isManager &&
                                      req.status == FundExpenseStatus.approved;
                                  final canReverse =
                                      isFamilyFund &&
                                      isManager &&
                                      (req.status ==
                                              FundExpenseStatus.approved ||
                                          req.status ==
                                              FundExpenseStatus.disputed);
                                  final canSubmitDraft =
                                      FundExpenseStateMachine.canUserSubmitDraft(
                                        currentStatus: req.status,
                                        actorUserId: user.id,
                                        requesterId: req.requesterId,
                                      );
                                  final canCancel =
                                      FundExpenseStateMachine.canUserCancel(
                                        currentStatus: req.status,
                                        actorUserId: user.id,
                                        requesterId: req.requesterId,
                                      );
                                  final blockedSelfApproval =
                                      isFamilyFund &&
                                      isManager &&
                                      req.status ==
                                          FundExpenseStatus.pendingApproval &&
                                      req.requesterId == user.id &&
                                      memberCount > 1;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: LifeOsSoftCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const LifeOsIconSquircle(
                                                icon:
                                                    Icons.receipt_long_rounded,
                                                tone: LifeOsAccentTone.amber,
                                                size: 40,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      req.title,
                                                      softWrap: true,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 14.8,
                                                        color: c.textPrimary,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${fund.name} · Đề xuất bởi ${req.requesterName} · ${dtFmt.format(req.createdAt)}',
                                                      softWrap: true,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: c.textSecondary,
                                                      ),
                                                    ),
                                                    if (req.disputeReason !=
                                                            null &&
                                                        req
                                                            .disputeReason!
                                                            .isNotEmpty) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Lý do khiếu nại: ${req.disputeReason}',
                                                        softWrap: true,
                                                        style: TextStyle(
                                                          fontSize: 11.8,
                                                          color: c.error,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                      maxWidth: 120,
                                                    ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: Text(
                                                    '-${VndAmount.format(req.amountMinor)}',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: c.error,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              SemanticStatusBadge(
                                                kind: _expenseBadgeKind(
                                                  req.status,
                                                ),
                                                label:
                                                    req.status.displayLabelVi,
                                              ),
                                              if (canSubmitDraft)
                                                FilledButton.icon(
                                                  key: Key(
                                                    'submit_draft_fund_exp_${req.id}',
                                                  ),
                                                  onPressed: state.isSaving
                                                      ? null
                                                      : () => context
                                                            .read<BudgetBloc>()
                                                            .add(
                                                              FundExpenseDraftSubmitted(
                                                                SubmitFundExpenseDraftParams(
                                                                  scope: fund
                                                                      .scope,
                                                                  userId:
                                                                      user.id,
                                                                  familyId: fund
                                                                      .familyId,
                                                                  fundId:
                                                                      fund.id,
                                                                  expenseId:
                                                                      req.id,
                                                                ),
                                                              ),
                                                            ),
                                                  icon: const Icon(
                                                    Icons.send_rounded,
                                                    size: 16,
                                                  ),
                                                  label: const Text(
                                                    'Gửi duyệt',
                                                  ),
                                                ),
                                              if (canDecide) ...[
                                                FilledButton.icon(
                                                  key: Key(
                                                    'approve_fund_exp_${req.id}',
                                                  ),
                                                  onPressed: state.isSaving
                                                      ? null
                                                      : () => context
                                                            .read<BudgetBloc>()
                                                            .add(
                                                              FundExpenseDecisionSubmitted(
                                                                DecideFundExpenseParams(
                                                                  familyId: fund
                                                                      .familyId!,
                                                                  fundId:
                                                                      fund.id,
                                                                  expenseId:
                                                                      req.id,
                                                                  approve: true,
                                                                  actorUserId:
                                                                      user.id,
                                                                ),
                                                              ),
                                                            ),
                                                  icon: const Icon(
                                                    Icons.check_rounded,
                                                    size: 17,
                                                  ),
                                                  label: const Text(
                                                    'Duyệt chi',
                                                  ),
                                                ),
                                                OutlinedButton.icon(
                                                  key: Key(
                                                    'reject_fund_exp_${req.id}',
                                                  ),
                                                  onPressed: state.isSaving
                                                      ? null
                                                      : () => context
                                                            .read<BudgetBloc>()
                                                            .add(
                                                              FundExpenseDecisionSubmitted(
                                                                DecideFundExpenseParams(
                                                                  familyId: fund
                                                                      .familyId!,
                                                                  fundId:
                                                                      fund.id,
                                                                  expenseId:
                                                                      req.id,
                                                                  approve:
                                                                      false,
                                                                  actorUserId:
                                                                      user.id,
                                                                ),
                                                              ),
                                                            ),
                                                  icon: Icon(
                                                    Icons.close_rounded,
                                                    size: 17,
                                                    color: c.error,
                                                  ),
                                                  label: Text(
                                                    'Từ chối',
                                                    style: TextStyle(
                                                      color: c.error,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              if (canExecute)
                                                FilledButton.icon(
                                                  key: Key(
                                                    'execute_fund_exp_${req.id}',
                                                  ),
                                                  onPressed: state.isSaving
                                                      ? null
                                                      : () => context
                                                            .read<BudgetBloc>()
                                                            .add(
                                                              FundExpenseExecuted(
                                                                ExecuteFundExpenseParams(
                                                                  familyId: fund
                                                                      .familyId!,
                                                                  fundId:
                                                                      fund.id,
                                                                  expenseId:
                                                                      req.id,
                                                                  actorUserId:
                                                                      user.id,
                                                                ),
                                                              ),
                                                            ),
                                                  icon: const Icon(
                                                    Icons.payments_outlined,
                                                    size: 17,
                                                  ),
                                                  label: const Text(
                                                    'Giải ngân',
                                                  ),
                                                ),
                                              if (canReverse)
                                                OutlinedButton.icon(
                                                  key: Key(
                                                    'reverse_fund_exp_${req.id}',
                                                  ),
                                                  onPressed: state.isSaving
                                                      ? null
                                                      : () => context
                                                            .read<BudgetBloc>()
                                                            .add(
                                                              FundExpenseReversed(
                                                                ReverseFundExpenseParams(
                                                                  familyId: fund
                                                                      .familyId!,
                                                                  fundId:
                                                                      fund.id,
                                                                  expenseId:
                                                                      req.id,
                                                                  actorUserId:
                                                                      user.id,
                                                                ),
                                                              ),
                                                            ),
                                                  icon: const Icon(
                                                    Icons.undo_rounded,
                                                    size: 17,
                                                  ),
                                                  label: const Text('Hoàn tác'),
                                                ),
                                              if (canCancel)
                                                TextButton.icon(
                                                  key: Key(
                                                    'cancel_fund_exp_${req.id}',
                                                  ),
                                                  onPressed: state.isSaving
                                                      ? null
                                                      : () => context
                                                            .read<BudgetBloc>()
                                                            .add(
                                                              FundExpenseCancelled(
                                                                CancelFundExpenseParams(
                                                                  scope: fund
                                                                      .scope,
                                                                  userId:
                                                                      user.id,
                                                                  familyId: fund
                                                                      .familyId,
                                                                  fundId:
                                                                      fund.id,
                                                                  expenseId:
                                                                      req.id,
                                                                  actorUserId:
                                                                      user.id,
                                                                ),
                                                              ),
                                                            ),
                                                  icon: Icon(
                                                    Icons.cancel_outlined,
                                                    size: 16,
                                                    color: c.textSecondary,
                                                  ),
                                                  label: const Text(
                                                    'Hủy đề xuất',
                                                  ),
                                                ),
                                            ],
                                          ),
                                          if (blockedSelfApproval) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              'Cần quản trị viên khác phê duyệt để bảo đảm kiểm soát chéo.',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }),

                              if (decidedExpenses.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                LifeOsSoftCard(
                                  child: LifeOsDetailsDiscloseSection(
                                    label:
                                        'Chi tiết lịch sử duyệt chi (${decidedExpenses.length})',
                                    child: Column(
                                      children: [
                                        for (
                                          var i = 0;
                                          i < decidedExpenses.length;
                                          i++
                                        ) ...[
                                          if (i > 0) const Divider(height: 18),
                                          Builder(
                                            builder: (ctx) {
                                              final entry = decidedExpenses[i];
                                              final f = entry.fund;
                                              final exp = entry.item;
                                              final isFamilyFund =
                                                  f.scope == FundScope.family &&
                                                  f.familyId != null &&
                                                  f.familyId!.isNotEmpty;
                                              final isMgr =
                                                  isFamilyFund &&
                                                  family != null &&
                                                  family.id == f.familyId &&
                                                  family.isManager(user.id);
                                              final isExec =
                                                  exp.status ==
                                                  FundExpenseStatus.executed;
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              exp.title,
                                                              softWrap: true,
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: c
                                                                    .textPrimary,
                                                              ),
                                                            ),
                                                            Text(
                                                              '${f.name} · ${exp.requesterName} · ${dtFmt.format(exp.createdAt)}',
                                                              softWrap: true,
                                                              style: TextStyle(
                                                                fontSize: 11.8,
                                                                color: c
                                                                    .textSecondary,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .end,
                                                        children: [
                                                          Text(
                                                            '-${VndAmount.format(exp.amountMinor)}',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color:
                                                                  exp
                                                                      .status
                                                                      .affectsBalance
                                                                  ? c.error
                                                                  : c.textSecondary,
                                                              fontFeatures: const [
                                                                FontFeature.tabularFigures(),
                                                              ],
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 3,
                                                          ),
                                                          SemanticStatusBadge(
                                                            kind:
                                                                _expenseBadgeKind(
                                                                  exp.status,
                                                                ),
                                                            label: exp
                                                                .status
                                                                .displayLabelVi,
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                  if (isFamilyFund &&
                                                      isExec) ...[
                                                    const SizedBox(height: 8),
                                                    Wrap(
                                                      spacing: 8,
                                                      runSpacing: 6,
                                                      children: [
                                                        if (isMgr)
                                                          OutlinedButton.icon(
                                                            key: Key(
                                                              'reconcile_fund_exp_${exp.id}',
                                                            ),
                                                            onPressed:
                                                                state.isSaving
                                                                ? null
                                                                : () => _showReconcileDialog(
                                                                    ctx,
                                                                    familyId: f
                                                                        .familyId!,
                                                                    fundId:
                                                                        f.id,
                                                                    expenseId:
                                                                        exp.id,
                                                                    actorUserId:
                                                                        user.id,
                                                                  ),
                                                            icon: const Icon(
                                                              Icons
                                                                  .fact_check_outlined,
                                                              size: 16,
                                                            ),
                                                            label: const Text(
                                                              'Đối soát',
                                                            ),
                                                          ),
                                                        if (isMgr)
                                                          OutlinedButton.icon(
                                                            key: Key(
                                                              'reverse_exec_fund_exp_${exp.id}',
                                                            ),
                                                            onPressed:
                                                                state.isSaving
                                                                ? null
                                                                : () => ctx.read<BudgetBloc>().add(
                                                                    FundExpenseReversed(
                                                                      ReverseFundExpenseParams(
                                                                        familyId:
                                                                            f.familyId!,
                                                                        fundId:
                                                                            f.id,
                                                                        expenseId:
                                                                            exp.id,
                                                                        actorUserId:
                                                                            user.id,
                                                                      ),
                                                                    ),
                                                                  ),
                                                            icon: const Icon(
                                                              Icons
                                                                  .undo_rounded,
                                                              size: 16,
                                                            ),
                                                            label: const Text(
                                                              'Hoàn tác',
                                                            ),
                                                          ),
                                                        TextButton.icon(
                                                          key: Key(
                                                            'dispute_fund_exp_${exp.id}',
                                                          ),
                                                          onPressed:
                                                              state.isSaving
                                                              ? null
                                                              : () => _showDisputeDialog(
                                                                  ctx,
                                                                  familyId: f
                                                                      .familyId!,
                                                                  fundId: f.id,
                                                                  expenseId:
                                                                      exp.id,
                                                                  actorUserId:
                                                                      user.id,
                                                                ),
                                                          icon: Icon(
                                                            Icons
                                                                .report_problem_outlined,
                                                            size: 16,
                                                            color: c.error,
                                                          ),
                                                          label: Text(
                                                            'Khiếu nại',
                                                            style: TextStyle(
                                                              color: c.error,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 14),

                              // 5. "Đóng góp gần đây" Card
                              Row(
                                children: [
                                  Icon(
                                    Icons.history_rounded,
                                    size: 19,
                                    color: c.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Đóng góp gần đây',
                                      softWrap: true,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LifeOsSoftCard(
                                child: allContributions.isEmpty
                                    ? Text(
                                        'Chưa có lượt đóng góp nào. Nhấn "Nạp quỹ" trên mục tiêu quỹ để nạp khoản đóng góp đầu tiên.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: c.textSecondary,
                                        ),
                                      )
                                    : Column(
                                        children: [
                                          for (
                                            var i = 0;
                                            i < allContributions.take(6).length;
                                            i++
                                          ) ...[
                                            if (i > 0)
                                              const Divider(height: 20),
                                            Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: 18,
                                                  backgroundColor:
                                                      c.primarySubtle,
                                                  child: Text(
                                                    allContributions[i]
                                                            .item
                                                            .contributorName
                                                            .trim()
                                                            .isEmpty
                                                        ? 'U'
                                                        : allContributions[i]
                                                              .item
                                                              .contributorName
                                                              .trim()
                                                              .characters
                                                              .first
                                                              .toUpperCase(),
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: c.primary,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        allContributions[i]
                                                            .item
                                                            .contributorName,
                                                        softWrap: true,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 14.5,
                                                          color: c.textPrimary,
                                                        ),
                                                      ),
                                                      Text(
                                                        '${dtFmt.format(allContributions[i].item.createdAt)} · ${allContributions[i].fund.name}',
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
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                        maxWidth: 124,
                                                      ),
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: Text(
                                                      '+${VndAmount.format(allContributions[i].item.amountMinor)}',
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: c.primary,
                                                        fontFeatures: const [
                                                          FontFeature.tabularFigures(),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
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

  Future<void> _showCreateFundDialog(
    BuildContext context, {
    required String userId,
    String? familyId,
  }) async {
    final bloc = context.read<BudgetBloc>();
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateFundDialog(
        budgetBloc: bloc,
        userId: userId,
        familyId: familyId,
      ),
    );
  }

  Future<void> _showContributeSheet(
    BuildContext context, {
    required String userId,
    required String userName,
    required FundEntity fund,
    required List<WalletEntity> wallets,
  }) async {
    final budgetBloc = context.read<BudgetBloc>();
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (_) => _ContributeFundSheet(
        budgetBloc: budgetBloc,
        userId: userId,
        userName: userName,
        fund: fund,
        fundAssetPath: _resolveFundVisual(fund.name).asset,
        wallets: wallets,
      ),
    );
  }

  Future<void> _showRequestExpenseSheet(
    BuildContext context, {
    required String userId,
    required String userName,
    required FundEntity fund,
  }) async {
    final budgetBloc = context.read<BudgetBloc>();
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (_) => _RequestFundExpenseSheet(
        budgetBloc: budgetBloc,
        userId: userId,
        userName: userName,
        fund: fund,
      ),
    );
  }

  Future<void> _showReconcileDialog(
    BuildContext context, {
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
  }) async {
    final budgetBloc = context.read<BudgetBloc>();
    final txCtrl = TextEditingController();
    var isSubmitting = false;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dCtx, setDialogState) => AlertDialog(
          title: const Text('Đối soát chứng từ chi quỹ'),
          content: TextField(
            key: Key('reconcile_tx_input_$expenseId'),
            controller: txCtrl,
            enabled: !isSubmitting,
            decoration: const InputDecoration(
              labelText: 'Mã giao dịch ví / chứng từ',
              hintText: 'VD: tx_20261125_001',
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final txId = txCtrl.text.trim();
                      if (txId.isEmpty) {
                        LifeOsTopToast.show(
                          dCtx,
                          'Vui lòng nhập mã giao dịch đối soát.',
                          kind: LifeOsToastKind.warning,
                        );
                        return;
                      }
                      setDialogState(() => isSubmitting = true);
                      final opId = const Uuid().v4();
                      final res = await budgetBloc.submitAndAwait(
                        FundExpenseReconciled(
                          ReconcileFundExpenseParams(
                            familyId: familyId,
                            fundId: fundId,
                            expenseId: expenseId,
                            actorUserId: actorUserId,
                            reconciledTxId: txId,
                            operationId: opId,
                          ),
                        ),
                        operationId: opId,
                      );
                      if (!dialogCtx.mounted) return;
                      setDialogState(() => isSubmitting = false);
                      if (res.failure != null) {
                        if (budgetBloc.state.failure != res.failure) {
                          LifeOsTopToast.show(
                            dialogCtx,
                            res.failure!.message,
                            kind: LifeOsToastKind.error,
                          );
                        }
                        return;
                      }
                      Navigator.of(dialogCtx).pop();
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Xác nhận đối soát'),
            ),
          ],
        ),
      ),
    );
    txCtrl.dispose();
  }

  Future<void> _showDisputeDialog(
    BuildContext context, {
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
  }) async {
    final budgetBloc = context.read<BudgetBloc>();
    final reasonCtrl = TextEditingController();
    var isSubmitting = false;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dCtx, setDialogState) => AlertDialog(
          title: const Text('Khiếu nại khoản chi quỹ'),
          content: TextField(
            key: Key('dispute_reason_input_$expenseId'),
            controller: reasonCtrl,
            enabled: !isSubmitting,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Lý do khiếu nại (>= 2 ký tự)',
              hintText: 'VD: Số tiền thực chi khác với chứng từ',
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final reason = reasonCtrl.text.trim();
                      if (reason.length < 2) {
                        LifeOsTopToast.show(
                          dCtx,
                          'Vui lòng nhập lý do khiếu nại (>= 2 ký tự).',
                          kind: LifeOsToastKind.warning,
                        );
                        return;
                      }
                      setDialogState(() => isSubmitting = true);
                      final opId = const Uuid().v4();
                      final res = await budgetBloc.submitAndAwait(
                        FundExpenseDisputed(
                          DisputeFundExpenseParams(
                            familyId: familyId,
                            fundId: fundId,
                            expenseId: expenseId,
                            actorUserId: actorUserId,
                            reason: reason,
                            operationId: opId,
                          ),
                        ),
                        operationId: opId,
                      );
                      if (!dialogCtx.mounted) return;
                      setDialogState(() => isSubmitting = false);
                      if (res.failure != null) {
                        if (budgetBloc.state.failure != res.failure) {
                          LifeOsTopToast.show(
                            dialogCtx,
                            res.failure!.message,
                            kind: LifeOsToastKind.error,
                          );
                        }
                        return;
                      }
                      Navigator.of(dialogCtx).pop();
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Gửi khiếu nại'),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }
}

class _CreateFundDialog extends StatefulWidget {
  const _CreateFundDialog({
    required this.budgetBloc,
    required this.userId,
    this.familyId,
  });

  final BudgetBloc budgetBloc;
  final String userId;
  final String? familyId;

  @override
  State<_CreateFundDialog> createState() => _CreateFundDialogState();
}

class _CreateFundDialogState extends State<_CreateFundDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _targetCtrl = TextEditingController(
    text: '25000000',
  );
  late FundScope _scope =
      (widget.familyId != null && widget.familyId!.isNotEmpty)
      ? FundScope.family
      : FundScope.personal;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final familyId = widget.familyId;
    return AlertDialog(
      title: const Text('Tạo Mục tiêu Quỹ mới'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên quỹ mục tiêu',
                hintText: 'VD: Du lịch hè / Quỹ khẩn cấp',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _targetCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Mục tiêu tích lũy (VND)',
              ),
            ),
            if (familyId != null && familyId.isNotEmpty) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Quỹ chung Gia đình'),
                value: _scope == FundScope.family,
                onChanged: (v) => setState(
                  () => _scope = v ? FundScope.family : FundScope.personal,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () {
            if (_nameCtrl.text.trim().length < 2) {
              LifeOsTopToast.show(
                context,
                'Tên quỹ phải có ít nhất 2 ký tự.',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            final target = VndAmount.tryParseInput(_targetCtrl.text) ?? 0;
            widget.budgetBloc.add(
              FundCreateSubmitted(
                CreateFundParams(
                  userId: widget.userId,
                  familyId: _scope == FundScope.family ? familyId : null,
                  scope: _scope,
                  name: _nameCtrl.text,
                  targetAmountMinor: target,
                ),
              ),
            );
            Navigator.of(context).pop();
          },
          child: const Text('Tạo quỹ'),
        ),
      ],
    );
  }
}

class _ContributeFundSheet extends StatefulWidget {
  const _ContributeFundSheet({
    required this.budgetBloc,
    required this.userId,
    required this.userName,
    required this.fund,
    required this.fundAssetPath,
    required this.wallets,
  });

  final BudgetBloc budgetBloc;
  final String userId;
  final String userName;
  final FundEntity fund;
  final String fundAssetPath;
  final List<WalletEntity> wallets;

  @override
  State<_ContributeFundSheet> createState() => _ContributeFundSheetState();
}

class _ContributeFundSheetState extends State<_ContributeFundSheet> {
  final TextEditingController _amtCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  bool _deductFromWallet = false;
  late String? _selectedWalletId = widget.wallets.isNotEmpty
      ? widget.wallets.first.id
      : null;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final canDeductWallet = widget.wallets.isNotEmpty;
    return LiquidGlassSheetFrame(
      showHandle: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 6, 18, 20 + viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  BananaGlassIcon(
                    assetPath: widget.fundAssetPath,
                    fallbackIcon: Icons.savings_outlined,
                    size: 40,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Nạp vào "${widget.fund.name}"',
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
              TextField(
                key: const Key('contribute_fund_amount_input'),
                controller: _amtCtrl,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số tiền đóng góp (VND)',
                  hintText: 'VD: 2000000',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú (Tùy chọn)',
                  hintText: 'VD: Góp quỹ tháng này',
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                key: const Key('contribute_deduct_wallet_switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Đồng thời trừ từ Ví cá nhân'),
                subtitle: Text(
                  canDeductWallet
                      ? 'Ghi nhận giao dịch chi tiêu thật và nạp quỹ trong cùng một giao dịch an toàn'
                      : 'Chưa có ví cá nhân để trừ trực tiếp',
                ),
                value: _deductFromWallet && canDeductWallet,
                onChanged: canDeductWallet && !_isSubmitting
                    ? (v) => setState(() => _deductFromWallet = v)
                    : null,
              ),
              if (_deductFromWallet && canDeductWallet) ...[
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedWalletId,
                  decoration: const InputDecoration(
                    labelText: 'Chọn ví nguồn thanh toán',
                  ),
                  items: widget.wallets
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
                  onChanged: _isSubmitting
                      ? null
                      : (v) => setState(() => _selectedWalletId = v),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Hủy'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('submit_contribute_fund_btn'),
                      onPressed: _isSubmitting
                          ? null
                          : () async {
                              final amt =
                                  VndAmount.tryParseInput(_amtCtrl.text) ?? 0;
                              if (amt <= 0) {
                                LifeOsTopToast.show(
                                  context,
                                  'Vui lòng nhập số tiền đóng góp > 0 ₫.',
                                  kind: LifeOsToastKind.warning,
                                );
                                return;
                              }
                              final selectedWalletId =
                                  _deductFromWallet && canDeductWallet
                                  ? _selectedWalletId
                                  : null;
                              if (_deductFromWallet &&
                                  canDeductWallet &&
                                  (selectedWalletId == null ||
                                      selectedWalletId.isEmpty)) {
                                LifeOsTopToast.show(
                                  context,
                                  'Vui lòng chọn ví nguồn thanh toán.',
                                  kind: LifeOsToastKind.warning,
                                );
                                return;
                              }
                              setState(() => _isSubmitting = true);
                              final opId = const Uuid().v4();
                              final trimmedNote = _noteCtrl.text.trim();
                              final res = await widget.budgetBloc
                                  .submitAndAwait(
                                    FundContributionSubmitted(
                                      ContributeFundParams(
                                        userId: widget.userId,
                                        userName: widget.userName,
                                        scope: widget.fund.scope,
                                        familyId: widget.fund.familyId,
                                        fundId: widget.fund.id,
                                        amountMinor: amt,
                                        note: trimmedNote.isEmpty
                                            ? null
                                            : trimmedNote,
                                        sourceWalletId: selectedWalletId,
                                        operationId: opId,
                                      ),
                                    ),
                                    operationId: opId,
                                  );
                              if (!context.mounted) return;
                              setState(() => _isSubmitting = false);
                              if (res.failure != null) {
                                if (widget.budgetBloc.state.failure !=
                                    res.failure) {
                                  LifeOsTopToast.show(
                                    context,
                                    res.failure!.message,
                                    kind: LifeOsToastKind.error,
                                  );
                                }
                                return;
                              }
                              Navigator.of(context).pop();
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
                          : const Text('Xác nhận nạp'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestFundExpenseSheet extends StatefulWidget {
  const _RequestFundExpenseSheet({
    required this.budgetBloc,
    required this.userId,
    required this.userName,
    required this.fund,
  });

  final BudgetBloc budgetBloc;
  final String userId;
  final String userName;
  final FundEntity fund;

  @override
  State<_RequestFundExpenseSheet> createState() =>
      _RequestFundExpenseSheetState();
}

class _RequestFundExpenseSheetState extends State<_RequestFundExpenseSheet> {
  final TextEditingController _reasonCtrl = TextEditingController();
  final TextEditingController _amtCtrl = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _amtCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitExpense(
    BuildContext ctx, {
    required bool saveAsDraft,
  }) async {
    final reason = _reasonCtrl.text.trim();
    final amt = VndAmount.tryParseInput(_amtCtrl.text) ?? 0;
    if (reason.length < 2 || amt <= 0) {
      LifeOsTopToast.show(
        ctx,
        'Vui lòng nhập lý do (>= 2 ký tự) và số tiền > 0 ₫.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }
    setState(() => _isSubmitting = true);
    final opId = const Uuid().v4();
    final res = await widget.budgetBloc.submitAndAwait(
      FundExpenseRequested(
        RequestFundExpenseParams(
          userId: widget.userId,
          userName: widget.userName,
          scope: widget.fund.scope,
          familyId: widget.fund.familyId,
          fundId: widget.fund.id,
          title: reason,
          amountMinor: amt,
          // Never auto-approve family expenses on client or server.
          canAutoApprove:
              widget.fund.scope == FundScope.personal && !saveAsDraft,
          saveAsDraft: saveAsDraft,
          operationId: opId,
        ),
      ),
      operationId: opId,
    );
    if (!ctx.mounted) return;
    setState(() => _isSubmitting = false);
    if (res.failure != null) {
      if (widget.budgetBloc.state.failure != res.failure) {
        LifeOsTopToast.show(
          ctx,
          res.failure!.message,
          kind: LifeOsToastKind.error,
        );
      }
      return;
    }
    Navigator.of(ctx).pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<BudgetBloc>.value(
      value: widget.budgetBloc,
      child: BlocBuilder<BudgetBloc, BudgetState>(
        builder: (ctx, bState) {
          final c = TammySemanticColors.of(ctx);
          final viewInsets = MediaQuery.viewInsetsOf(ctx);
          final busy = _isSubmitting || bState.isSaving;
          final isFamily = widget.fund.scope == FundScope.family;
          return LiquidGlassSheetFrame(
            showHandle: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 6, 18, 20 + viewInsets.bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const LifeOsIconSquircle(
                          icon: Icons.outbox_rounded,
                          tone: LifeOsAccentTone.amber,
                          size: 40,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Đề xuất chi / Rút quỹ "${widget.fund.name}"',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                'Số dư hiện có: ${VndAmount.format(widget.fund.balanceMinor)}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: c.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('fund_expense_amount_input'),
                      controller: _amtCtrl,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Số tiền đề xuất chi (VND)',
                        hintText: 'VD: 500000',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('fund_expense_reason_input'),
                      controller: _reasonCtrl,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Lý do / Mục đích chi quỹ',
                        hintText: 'VD: Đặt phòng khách sạn Đà Lạt',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isFamily
                          ? 'Khoản đề xuất từ quỹ chung sẽ chờ quản trị viên phê duyệt và giải ngân trước khi trừ quỹ.'
                          : 'Khoản rút từ quỹ cá nhân sẽ được trừ trực tiếp vào số dư quỹ nếu đủ số dư.',
                      softWrap: true,
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.of(ctx).pop(),
                          child: const Text('Hủy'),
                        ),
                        if (isFamily)
                          OutlinedButton(
                            key: const Key('save_draft_fund_expense_btn'),
                            onPressed: busy
                                ? null
                                : () => _submitExpense(ctx, saveAsDraft: true),
                            child: const Text('Lưu nháp'),
                          ),
                        FilledButton(
                          key: const Key('submit_fund_expense_btn'),
                          onPressed: busy
                              ? null
                              : () => _submitExpense(ctx, saveAsDraft: false),
                          child: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  isFamily
                                      ? 'Gửi đề xuất chi'
                                      : 'Xác nhận rút quỹ',
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
