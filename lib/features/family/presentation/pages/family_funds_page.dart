import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../budgets/domain/entities/budget_entities.dart';
import '../../../budgets/domain/usecases/budget_usecases.dart';
import '../../../budgets/presentation/bloc/budget_bloc.dart';
import '../bloc/family_bloc.dart';

/// Screen 08: "Quỹ gia đình" (`08_Quy_gia_dinh.png`) following Unified LifeOS Design System.
class FamilyFundsPage extends StatelessWidget {
  const FamilyFundsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = TammySemanticColors.of(context);
    final family = context.watch<FamilyBloc>().state.activeFamily;
    final dtFmt = DateFormat('dd/MM, HH:mm');

    return BlocListener<BudgetBloc, BudgetState>(
      listenWhen: (p, c) =>
          p.failure != c.failure || p.actionMessage != c.actionMessage,
      listener: (context, state) {
        if (state.failure != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text('⚠ ${state.failure!.message}')),
          );
        } else if (state.actionMessage != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text('✓ ${state.actionMessage!}')),
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

                      final totalIn = allContributions.fold<int>(
                        0,
                        (s, e) => s + e.item.amountMinor,
                      );
                      final totalOut = funds
                          .expand((f) => f.expenseRequests)
                          .where((r) => r.status == FundExpenseStatus.approved)
                          .fold<int>(0, (s, r) => s + r.amountMinor);

                      final monthlyGoal = totalTarget > 0
                          ? totalTarget
                          : 20000000;
                      final monthlyPct = monthlyGoal > 0
                          ? ((totalBalance * 100) / monthlyGoal)
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
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.savings_outlined,
                                                    size: 19,
                                                    color: c.primary,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      'Tổng quỹ hiện tại',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                                              const SizedBox(height: 6),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  VndAmount.format(
                                                    totalBalance,
                                                  ),
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
                                                  size: 36,
                                                  iconSize: 18,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Tiền vào (Thu)',
                                                        style: TextStyle(
                                                          fontSize: 11.8,
                                                          color:
                                                              c.textSecondary,
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
                                                      Text(
                                                        'Tháng này',
                                                        style: TextStyle(
                                                          fontSize: 11.2,
                                                          color:
                                                              c.textSecondary,
                                                        ),
                                                      ),
                                                    ],
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
                                            child: Row(
                                              children: [
                                                const LifeOsIconSquircle(
                                                  icon: Icons
                                                      .arrow_upward_rounded,
                                                  tone: LifeOsAccentTone.coral,
                                                  size: 36,
                                                  iconSize: 18,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Tiền ra (Chi)',
                                                        style: TextStyle(
                                                          fontSize: 11.8,
                                                          color:
                                                              c.textSecondary,
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
                                                      Text(
                                                        'Tháng này',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              c.textSecondary,
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
                                            'Đóng góp tháng này',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.info_outline_rounded,
                                          size: 18,
                                          color: c.textSecondary,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
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
                                                ' / ${VndAmount.format(monthlyGoal)}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: c.textSecondary,
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
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: LinearProgressIndicator(
                                              minHeight: 9,
                                              value: (monthlyPct / 100).clamp(
                                                0.0,
                                                1.0,
                                              ),
                                              backgroundColor: c.surfaceRaised,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    c.primary,
                                                  ),
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
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              // 3. "Mục tiêu quỹ" Section Header + Cards
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.track_changes_rounded,
                                        size: 19,
                                        color: c.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Mục tiêu quỹ',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  TextButton(
                                    onPressed: () => _showCreateFundDialog(
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
                                      const LifeOsIconSquircle(
                                        icon: Icons.luggage_outlined,
                                        tone: LifeOsAccentTone.blue,
                                        size: 46,
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
                                        'Khởi tạo Quỹ du lịch hè, Quỹ khẩn cấp hoặc Quỹ học tập để cả nhà cùng đóng góp minh bạch.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ...funds.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final fund = entry.value;
                                  final isTravel = idx.isEven;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: LifeOsSoftCard(
                                      onTap: () => _showContributeDialog(
                                        context,
                                        userId: user.id,
                                        userName: user.fullName,
                                        fund: fund,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              LifeOsIconSquircle(
                                                icon: isTravel
                                                    ? Icons.luggage_outlined
                                                    : Icons
                                                          .health_and_safety_outlined,
                                                tone: isTravel
                                                    ? LifeOsAccentTone.blue
                                                    : LifeOsAccentTone.emerald,
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
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 15.5,
                                                        color: c.textPrimary,
                                                      ),
                                                    ),
                                                    Text(
                                                      fund.scope ==
                                                              FundScope.family
                                                          ? 'Quỹ chung gia đình'
                                                          : 'Quỹ tích lũy cá nhân',
                                                      style: TextStyle(
                                                        fontSize: 12.5,
                                                        color: c.textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              FilledButton.tonal(
                                                onPressed: () =>
                                                    _showContributeDialog(
                                                      context,
                                                      userId: user.id,
                                                      userName: user.fullName,
                                                      fund: fund,
                                                    ),
                                                child: const Text('Nạp quỹ'),
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
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.textPrimary,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                                TextSpan(
                                                  text:
                                                      ' / ${VndAmount.format(fund.targetAmountMinor)}',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: LinearProgressIndicator(
                                                    minHeight: 8,
                                                    value:
                                                        (fund.progressPct / 100)
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
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),

                              const SizedBox(height: 14),

                              // 4. "Đóng góp gần đây" Card
                              Row(
                                children: [
                                  Icon(
                                    Icons.history_rounded,
                                    size: 19,
                                    color: c.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Đóng góp gần đây',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LifeOsSoftCard(
                                child: allContributions.isEmpty
                                    ? Text(
                                        'Chưa có lượt đóng góp nào. Nhấn vào mục tiêu quỹ để nạp khoản đóng góp đầu tiên.',
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
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 14.5,
                                                          color: c.textPrimary,
                                                        ),
                                                      ),
                                                      Text(
                                                        '${dtFmt.format(allContributions[i].item.createdAt)} · ${allContributions[i].fund.name}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              c.textSecondary,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Text(
                                                  '+${VndAmount.format(allContributions[i].item.amountMinor)}',
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
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
    final nameCtrl = TextEditingController();
    final targetCtrl = TextEditingController(text: '25000000');
    var scope = (familyId != null && familyId.isNotEmpty)
        ? FundScope.family
        : FundScope.personal;
    final bloc = context.read<BudgetBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Tạo Mục tiêu Quỹ mới'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên quỹ mục tiêu',
                  hintText: 'VD: Du lịch hè / Quỹ khẩn cấp',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: targetCtrl,
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
                  value: scope == FundScope.family,
                  onChanged: (v) => setDialogState(
                    () => scope = v ? FundScope.family : FundScope.personal,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final target = VndAmount.tryParseInput(targetCtrl.text) ?? 0;
                bloc.add(
                  FundCreateSubmitted(
                    CreateFundParams(
                      userId: userId,
                      familyId: scope == FundScope.family ? familyId : null,
                      scope: scope,
                      name: nameCtrl.text,
                      targetAmountMinor: target,
                    ),
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Tạo quỹ'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    targetCtrl.dispose();
  }

  Future<void> _showContributeDialog(
    BuildContext context, {
    required String userId,
    required String userName,
    required FundEntity fund,
  }) async {
    final amtCtrl = TextEditingController(text: '2000000');
    final noteCtrl = TextEditingController();
    final bloc = context.read<BudgetBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nạp vào "${fund.name}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền đóng góp (VND)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Ghi chú (Tùy chọn)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final amt = VndAmount.tryParseInput(amtCtrl.text) ?? 0;
              bloc.add(
                FundContributionSubmitted(
                  ContributeFundParams(
                    userId: userId,
                    userName: userName,
                    scope: fund.scope,
                    familyId: fund.familyId,
                    fundId: fund.id,
                    amountMinor: amt,
                    note: noteCtrl.text,
                  ),
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Xác nhận nạp'),
          ),
        ],
      ),
    );
    amtCtrl.dispose();
    noteCtrl.dispose();
  }
}
