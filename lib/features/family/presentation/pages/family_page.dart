import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/vietqr_settlement_sheet.dart';
import '../../../../core/widgets/voice_smart_capture_sheet.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_event.dart';
import '../../../budgets/presentation/bloc/budget_bloc.dart';
import '../../../calendar/presentation/bloc/calendar_bloc.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../domain/entities/family_entities.dart';
import '../../domain/usecases/family_usecases.dart';
import '../bloc/family_bloc.dart';

class FamilyPage extends StatelessWidget {
  const FamilyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return BlocListener<FamilyBloc, FamilyState>(
      listenWhen: (p, c) =>
          p.failure != c.failure ||
          p.message != c.message ||
          p.selectedFamilyId != c.selectedFamilyId,
      listener: (context, state) {
        if (state.selectedFamilyId != null && state.selectedFamilyId != user.activeFamilyId) {
          context.read<AuthBloc>().add(AuthActiveFamilyChanged(state.selectedFamilyId!));
        }
        if (state.failure != null) {
          LifeOsTopToast.fromSnackBar(context, SnackBar(content: Text('⚠ ${state.failure!.message}')));
        } else if (state.message != null) {
          LifeOsTopToast.fromSnackBar(context, SnackBar(content: Text('✓ ${state.message!}')));
        }
      },
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              child: Column(
                children: [
                  LifeOsTopBrandHeader(
                    title: 'Gia đình',
                    subtitle: 'Phối hợp cùng nhau, quản lý việc nhà, lịch và tài chính chung an toàn.',
                    extraBrandActions: [
                      LifeOsHeaderCircleButton(
                        icon: Icons.mic_rounded,
                        tooltip: 'Nói câu chia tiền nhóm bằng Giọng nói AI',
                        onTap: () => showVoiceSmartCaptureSheet(
                          context,
                          initialTranscript: 'Ăn lẩu bò 450 nghìn chia đều 3 người',
                        ),
                      ),
                      LifeOsHeaderCircleButton(
                        icon: Icons.group_add_outlined,
                        tooltip: 'Nhập mã mời',
                        onTap: () => _showJoinFamilyDialog(context, user.id, user.fullName),
                      ),
                    ],
                    trailingAction: FilledButton.icon(
                      key: const Key('open_create_space_button'),
                      onPressed: () => _showCreateFamilyDialog(context, user.id, user.fullName),
                      icon: const Icon(Icons.add_home_outlined, size: 18),
                      label: const Text('Tạo nhóm'),
                    ),
                  ),
                  Expanded(
                    child: BlocBuilder<FamilyBloc, FamilyState>(
                      builder: (context, state) {
                        final family = state.activeFamily;
                        if (family == null) {
                          return EmptyStateView(
                            icon: Icons.family_restroom_rounded,
                            imageAsset: AppAssets.familySplitIllustration,
                            title: 'Chưa tham gia Gia đình / Nhóm Ở ghép / Hội nhóm nào',
                            subtitle:
                                'Tạo không gian mới (Hộ gia đình, Nhà trọ ở ghép hoặc Hội nhóm chuyến đi) để chia tiền ăn uống, việc nhà, điện nước, quỹ chung & tài liệu mà không lộ ví cá nhân.',
                            actionLabel: 'Khởi tạo không gian đầu tiên',
                            onAction: () =>
                                _showCreateFamilyDialog(context, user.id, user.fullName),
                          );
                        }

                        return Column(
                          children: [
                            if (state.families.length > 1)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.md,
                                  4,
                                  AppSpacing.md,
                                  0,
                                ),
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: family.id,
                                    decoration: const InputDecoration(
                                      labelText: 'Chuyển không gian cộng tác đang xem',
                                      isDense: true,
                                    ),
                                    items: state.families
                                        .map(
                                          (f) => DropdownMenuItem(
                                            value: f.id,
                                            child: Text(
                                              '${f.name} · ${f.spaceType.displayLabel}',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (nextId) {
                                      if (nextId != null) {
                                        context
                                            .read<FamilyBloc>()
                                            .add(FamilyShoppingWatchRequested(nextId));
                                      }
                                    },
                                  ),
                                ),
                              ),
                            const ProPillTabContainer(
                              tabBar: TabBar(
                                tabs: [
                                  Tab(
                                    key: Key('family_split_tab'),
                                    text: 'Tổng quan & Chia',
                                  ),
                                  Tab(
                                    key: Key('family_members_tab'),
                                    text: 'Thành viên',
                                  ),
                                  Tab(
                                    key: Key('family_shopping_tab'),
                                    text: 'Mua sắm',
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _SplitBillsAndSettlementTabView(
                                    family: family,
                                    state: state,
                                    currentUserId: user.id,
                                    currentUserName: user.fullName,
                                  ),
                                  _MembersAndGovernanceTabView(
                                    family: family,
                                    state: state,
                                    currentUserId: user.id,
                                  ),
                                  _SharedShoppingTabView(
                                    family: family,
                                    state: state,
                                    currentUserName: user.fullName,
                                  ),
                                ],
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

  Future<void> _showCreateFamilyDialog(
    BuildContext context,
    String userId,
    String userName,
  ) async {
    final ctrl = TextEditingController();
    var selectedType = CollaborationSpaceType.family;
    final bloc = context.read<FamilyBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Khởi tạo Không gian Cộng tác Mới'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Mô hình vận hành'),
                const SizedBox(height: 6),
                DropdownButtonFormField<CollaborationSpaceType>(
                  isExpanded: true,
                  initialValue: selectedType,
                  items: CollaborationSpaceType.values
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.displayLabel, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedType = v);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  selectedType.subtitleHint,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('Tên gọi không gian'),
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    hintText: 'VD: Tổ ấm Minh & Lan / Căn hộ P.802 / Team Đà Lạt',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
            FilledButton(
              onPressed: () {
                bloc.add(
                  FamilyCreateSubmitted(
                    userId: userId,
                    userName: userName,
                    familyName: ctrl.text,
                    spaceType: selectedType,
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Tạo'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showJoinFamilyDialog(
    BuildContext context,
    String userId,
    String userName,
  ) async {
    final ctrl = TextEditingController();
    final bloc = context.read<FamilyBloc>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tham gia bằng Mã mời 7 ngày'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Mã mời (VD: FAM-8K2P9Q)'),
            const SizedBox(height: 6),
            TextField(controller: ctrl),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              bloc.add(
                FamilyJoinByCodeSubmitted(
                  userId: userId,
                  userName: userName,
                  inviteCode: ctrl.text,
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Tham gia'),
          ),
        ],
      ),
    );
  }
}

class _SplitBillsAndSettlementTabView extends StatelessWidget {
  final FamilyEntity family;
  final FamilyState state;
  final String currentUserId;
  final String currentUserName;

  const _SplitBillsAndSettlementTabView({
    required this.family,
    required this.state,
    required this.currentUserId,
    required this.currentUserName,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final ledger = state.sharedLedger;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          key: const Key('split_bills_list_view'),
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            // Unified LifeOS "Tổng quan gia đình" Pastel Mint Hero Card (`06_Gia_dinh.png`)
            Builder(
              builder: (context) {
                final taskCount = context.watch<TaskBloc>().state.tasks.length;
                final eventCount = context.watch<CalendarBloc>().state.events.length;
                final totalFunds = context
                    .watch<BudgetBloc>()
                    .state
                    .funds
                    .fold<int>(0, (s, f) => s + f.balanceMinor);
                final displayFund =
                    totalFunds > 0 ? totalFunds : ledger.totalSharedSpendMinor;

                return LifeOsMintHeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.groups_outlined, size: 20, color: c.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              family.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          const LifeOsStatusPill(
                            icon: Icons.verified_user_outlined,
                            label: 'Chia sẻ an toàn',
                            tone: LifeOsAccentTone.emerald,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          LifeOsAvatarStack(
                            names: family.members.map((m) => m.fullName).toList(),
                            radius: 16,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '🔒 Chỉ thành viên trong nhóm mới xem được\n👥 Phối hợp, phân công & chia khoản công bằng',
                              style: TextStyle(
                                fontSize: 11.8,
                                height: 1.38,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 22),
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => context.push('/tasks-board'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Việc chung',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      '$taskCount',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: c.primary,
                                      ),
                                    ),
                                    Text(
                                      'việc cần làm',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            VerticalDivider(width: 12, color: c.separator),
                            Expanded(
                              child: InkWell(
                                onTap: () => context.go('/planning'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Lịch chung',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      '$eventCount',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: c.primary,
                                      ),
                                    ),
                                    Text(
                                      'sự kiện',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            VerticalDivider(width: 12, color: c.separator),
                            Expanded(
                              flex: 2,
                              child: InkWell(
                                onTap: () => context.push('/family-funds'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Quỹ & Chi chung',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      VndAmount.format(displayFund),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: c.textPrimary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      'Nhấn mở Quỹ chung >',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: c.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const Key('open_add_split_bill_button'),
                            onPressed: () => _showCreateSplitBillDialog(context),
                            icon: const Icon(Icons.call_split_rounded, size: 18),
                            label: const Text('Chia khoản mới'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.push('/family-funds'),
                            icon: const Icon(Icons.savings_outlined, size: 17),
                            label: const Text('Quỹ chung'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.push('/family-documents'),
                            icon: const Icon(Icons.folder_open_rounded, size: 17),
                            label: const Text('Tài liệu'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.push('/tasks-board'),
                            icon: const Icon(Icons.task_alt_rounded, size: 17),
                            label: const Text('Giao việc'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: AppSpacing.md),
            Text(
              'Số dư Ròng từng Thành viên (Ứng trước vs Phải chịu)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  children: ledger.memberBalances.map((mb) {
                    final isPositive = mb.netBalanceMinor > 0;
                    final isNegative = mb.netBalanceMinor < 0;
                    final statusColor =
                        isPositive ? c.success : (isNegative ? c.error : c.textSecondary);
                    final statusLabel = isPositive
                        ? 'Cần nhận lại ${VndAmount.format(mb.netBalanceMinor)}'
                        : isNegative
                            ? 'Đang nợ nhóm ${VndAmount.format(mb.netBalanceMinor.abs())}'
                            : 'Đã cân bằng (0 ₫)';

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        child: Text(
                          mb.fullName.isNotEmpty ? mb.fullName[0].toUpperCase() : '?',
                        ),
                      ),
                      title: Text(mb.fullName),
                      subtitle: Text(
                        'Đã trả hộ: ${VndAmount.format(mb.totalPaidMinor)} · Phần chịu: ${VndAmount.format(mb.totalOwedMinor)}',
                      ),
                      trailing: Text(
                        statusLabel,
                        style: TextStyle(fontWeight: FontWeight.w700, color: statusColor),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.md),
            Text(
              'Lộ trình Tất toán Tối giản Công nợ (Chuẩn mã SePay SEVQR)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (ledger.suggestedTransfers.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    'Tuyệt vời! Mọi khoản ăn uống, việc nhà và hóa đơn chung hiện đã cân bằng 100%.',
                  ),
                ),
              )
            else
              ...ledger.suggestedTransfers.map(
                (tr) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${tr.fromUserName} → ${tr.toUserName}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                VndAmount.format(tr.amountMinor),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: c.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Nội dung CK: ${tr.sePayTransferCode}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  showVietQrSettlementSheet(
                                    context: context,
                                    fromName: tr.fromUserName,
                                    toName: tr.toUserName,
                                    amountMinor: tr.amountMinor,
                                    sePayCode: tr.sePayTransferCode,
                                    onConfirmSettled: () {
                                      context.read<FamilyBloc>().add(
                                            DebtSettlementRecorded(
                                              RecordDebtSettlementParams(
                                                familyId: family.id,
                                                fromUserId: tr.fromUserId,
                                                fromUserName: tr.fromUserName,
                                                toUserId: tr.toUserId,
                                                toUserName: tr.toUserName,
                                                amountMinor: tr.amountMinor,
                                                paymentCode: tr.sePayTransferCode,
                                              ),
                                            ),
                                          );
                                    },
                                  );
                                },
                                icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                                label: const Text('Mã QR'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: tr.sePayTransferCode));
                                  LifeOsTopToast.fromSnackBar(context, 
                                    const SnackBar(
                                      content: Text('✓ Đã sao chép mã chuyển khoản SEVQR.'),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded, size: 15),
                                label: const Text('Copy mã'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  context.read<FamilyBloc>().add(
                                        DebtSettlementRecorded(
                                          RecordDebtSettlementParams(
                                            familyId: family.id,
                                            fromUserId: tr.fromUserId,
                                            fromUserName: tr.fromUserName,
                                            toUserId: tr.toUserId,
                                            toUserName: tr.toUserName,
                                            amountMinor: tr.amountMinor,
                                            paymentCode: tr.sePayTransferCode,
                                          ),
                                        ),
                                      );
                                },
                                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                                label: const Text('Ghi nhận đã tất toán'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: AppSpacing.lg),
            Text(
              'Sổ Khoản chi Chung (${state.sharedBills.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (state.sharedBills.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    'Chưa có khoản chia tiền nào. Nhấn "Chia khoản mới" để chia tiền ăn uống, việc nhà, tiền trọ hoặc chuyến đi.',
                  ),
                ),
              )
            else
              ...state.sharedBills.map(
                (bill) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.receipt_long_rounded)),
                      title: Text('${bill.title} · ${VndAmount.format(bill.totalAmountMinor)}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${bill.topic.displayLabel} · Trả trước bởi ${bill.paidByName} · ${bill.splitMethod.displayLabel}',
                          ),
                          if (bill.choreOrTaskNote != null && bill.choreOrTaskNote!.isNotEmpty)
                            Text(
                              'Gắn việc nhà / ghi chú: ${bill.choreOrTaskNote}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          Text(
                            'Phần chia: ${bill.sharesByUserId.entries.map((e) => '${bill.participantNames[e.key] ?? 'TV'}: ${VndAmount.format(e.value)}').join(' · ')}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            if (state.settlements.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Lịch sử Tất toán (${state.settlements.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              ...state.settlements.take(10).map(
                    (st) => Card(
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.verified_rounded, color: c.success),
                        title: Text(
                          '${st.fromUserName} đã trả ${st.toUserName}: ${VndAmount.format(st.amountMinor)}',
                        ),
                        subtitle: Text('Mã đối soát: ${st.paymentCode}'),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateSplitBillDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final totalCtrl = TextEditingController();
    final choreCtrl = TextEditingController();
    var topic = SharedExpenseTopic.dining;
    var method = SplitMethod.equal;
    var payerId = family.members.any((m) => m.userId == currentUserId)
        ? currentUserId
        : family.members.first.userId;

    final selectedIds = <String>{for (final m in family.members) m.userId};
    final perMemberCtrls = <String, TextEditingController>{
      for (final m in family.members) m.userId: TextEditingController(text: '1'),
    };
    final bloc = context.read<FamilyBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Chia Tiền Ăn uống · Việc nhà · Sinh hoạt'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Nhóm khoản chung'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<SharedExpenseTopic>(
                    isExpanded: true,
                    initialValue: topic,
                    items: SharedExpenseTopic.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.displayLabel, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => topic = v);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Nội dung chi tiêu'),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('split_bill_title_input'),
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      hintText: 'VD: Lẩu cuối tuần / Mua nước lau sàn & giặt ủi',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Tổng số tiền (VND)'),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('split_bill_amount_input'),
                    controller: totalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '300000'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Ai là người ứng tiền trả trước?'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: payerId,
                    items: family.members
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.userId,
                            child: Text(m.fullName, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => payerId = v);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Phương thức chia tiền'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<SplitMethod>(
                    isExpanded: true,
                    initialValue: method,
                    items: SplitMethod.values
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(m.displayLabel, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() {
                          method = v;
                          if (method == SplitMethod.percentage && selectedIds.isNotEmpty) {
                            final basePct = 100 ~/ selectedIds.length;
                            var rem = 100 % selectedIds.length;
                            for (final uid in selectedIds) {
                              final add = rem > 0 ? 1 : 0;
                              if (rem > 0) rem -= 1;
                              perMemberCtrls[uid]?.text = '${basePct + add}';
                            }
                          } else if (method == SplitMethod.shares) {
                            for (final uid in selectedIds) {
                              perMemberCtrls[uid]?.text = '1';
                            }
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Thành viên tham gia'),
                  ...family.members.map((m) {
                    final checked = selectedIds.contains(m.userId);
                    return Column(
                      children: [
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: checked,
                          title: Text(m.fullName),
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedIds.add(m.userId);
                              } else if (selectedIds.length > 1) {
                                selectedIds.remove(m.userId);
                              }
                            });
                          },
                        ),
                        if (checked && method != SplitMethod.equal)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextField(
                              controller: perMemberCtrls[m.userId],
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: switch (method) {
                                  SplitMethod.percentage => 'Tỷ lệ % của ${m.fullName}',
                                  SplitMethod.shares => 'Số phần / hệ số của ${m.fullName}',
                                  SplitMethod.exact => 'Số tiền VND của ${m.fullName}',
                                  SplitMethod.equal => '',
                                },
                              ),
                            ),
                          ),
                      ],
                    );
                  }),
                  const SizedBox(height: AppSpacing.xs),
                  const Text('Gắn ghi chú Việc nhà / Nhiệm vụ (tùy chọn)'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: choreCtrl,
                    decoration: const InputDecoration(
                      hintText: 'VD: Ca trực nhật dọn bếp tuần này',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
              FilledButton(
                key: const Key('submit_split_bill_button'),
                onPressed: () {
                  final total = VndAmount.tryParseInput(totalCtrl.text) ?? 0;
                  final payerMember = family.members.firstWhere(
                    (m) => m.userId == payerId,
                    orElse: () => FamilyMemberInfo(
                      userId: currentUserId,
                      fullName: currentUserName,
                      role: HouseholdRole.member,
                    ),
                  );
                  final rawInputs = <String, int>{};
                  for (final uid in selectedIds) {
                    final rawTxt = perMemberCtrls[uid]?.text ?? '0';
                    rawInputs[uid] = method == SplitMethod.exact
                        ? (VndAmount.tryParseInput(rawTxt) ?? 0)
                        : (int.tryParse(rawTxt.trim()) ?? 0);
                  }
                  final namesMap = <String, String>{
                    for (final m in family.members) m.userId: m.fullName,
                  };

                  bloc.add(
                    SharedBillSplitCreated(
                      CreateSharedBillSplitParams(
                        familyId: family.id,
                        title: titleCtrl.text,
                        topic: topic,
                        paidByUserId: payerMember.userId,
                        paidByName: payerMember.fullName,
                        totalAmountMinor: total,
                        splitMethod: method,
                        participantIds: selectedIds.toList(),
                        participantNames: namesMap,
                        rawInputValuesByUserId: rawInputs,
                        choreOrTaskNote: choreCtrl.text,
                      ),
                    ),
                  );
                  Navigator.of(ctx).pop();
                },
                child: const Text('Lưu & Tính chia'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MembersAndGovernanceTabView extends StatelessWidget {
  final FamilyEntity family;
  final FamilyState state;
  final String currentUserId;

  const _MembersAndGovernanceTabView({
    required this.family,
    required this.state,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          key: const Key('members_list_view'),
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          family.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        SemanticStatusBadge(
                          kind: SemanticStatusKind.info,
                          label:
                              '${family.spaceType.displayLabel} · ${family.roleOf(currentUserId).name.toUpperCase()}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      family.spaceType.subtitleHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        if (family.isManager(currentUserId))
                          OutlinedButton.icon(
                            onPressed: () => context.read<FamilyBloc>().add(
                                  FamilyInviteGenerated(
                                    userId: currentUserId,
                                    familyId: family.id,
                                    familyName: family.name,
                                  ),
                                ),
                            icon: const Icon(Icons.qr_code_rounded, size: 18),
                            label: const Text('Tạo mã mời 7 ngày'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final ok = await showDestructiveConfirmDialog(
                              context: context,
                              title: 'Rời khỏi "${family.name}"?',
                              message:
                                  'Quyền truy cập dữ liệu chung sẽ thu hồi ngay lập tức. Ví và giao dịch cá nhân của bạn vẫn được giữ nguyên 100%.',
                              confirmLabel: 'Rời không gian',
                            );
                            if (ok && context.mounted) {
                              context.read<FamilyBloc>().add(
                                    FamilyLeaveConfirmed(
                                      userId: currentUserId,
                                      familyId: family.id,
                                    ),
                                  );
                            }
                          },
                          icon: const Icon(Icons.exit_to_app_rounded, size: 18),
                          label: const Text('Rời nhóm'),
                        ),
                      ],
                    ),
                    if (state.latestInviteCode != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Mã mời hiện tại: ${state.latestInviteCode}'),
                          IconButton(
                            tooltip: 'Sao chép mã mời',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: state.latestInviteCode!),
                              );
                              LifeOsTopToast.fromSnackBar(context, 
                                const SnackBar(content: Text('✓ Đã sao chép mã mời.')),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                          ),
                        ],
                      ),
                    ],
                    const Divider(height: 24),
                    Text(
                      'Thành viên (${family.members.length})',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    ...family.members.map(
                      (m) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                        title: Text(m.fullName),
                        trailing: SemanticStatusBadge(
                          kind: m.role == HouseholdRole.owner
                              ? SemanticStatusKind.success
                              : SemanticStatusKind.info,
                          label: m.role.name,
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
    );
  }
}

class _SharedShoppingTabView extends StatelessWidget {
  final FamilyEntity family;
  final FamilyState state;
  final String currentUserName;

  const _SharedShoppingTabView({
    required this.family,
    required this.state,
    required this.currentUserName,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          key: const Key('shopping_list_view'),
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Danh sách Mua sắm Chung (${state.shoppingItems.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showAddShoppingDialog(
                    context,
                    familyId: family.id,
                    userName: currentUserName,
                  ),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: const Text('Thêm món'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (state.shoppingItems.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text('Danh sách mua sắm chung đang trống.'),
                ),
              )
            else
              ...state.shoppingItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Card(
                    child: CheckboxListTile(
                      value: item.isPurchased,
                      onChanged: (checked) {
                        context.read<FamilyBloc>().add(
                              ShoppingItemToggled(
                                familyId: family.id,
                                itemId: item.id,
                                isPurchased: checked ?? false,
                              ),
                            );
                      },
                      title: Text(
                        '${item.title} (${item.quantityLabel})',
                        style: TextStyle(
                          decoration: item.isPurchased ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Text(
                        'Dự kiến: ${VndAmount.format(item.estimatedPriceMinor)} · Thêm bởi ${item.addedByName}',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddShoppingDialog(
    BuildContext context, {
    required String familyId,
    required String userName,
  }) async {
    final titleCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(text: '50000');
    final bloc = context.read<FamilyBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm Món vào Danh sách Mua sắm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tên hàng hóa'),
            const SizedBox(height: 6),
            TextField(controller: titleCtrl),
            const SizedBox(height: AppSpacing.sm),
            const Text('Số lượng'),
            const SizedBox(height: 6),
            TextField(controller: qtyCtrl),
            const SizedBox(height: AppSpacing.sm),
            const Text('Giá dự kiến (VND)'),
            const SizedBox(height: 6),
            TextField(controller: priceCtrl, keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              final est = VndAmount.tryParseInput(priceCtrl.text) ?? 0;
              bloc.add(
                ShoppingItemAdded(
                  familyId: familyId,
                  userName: userName,
                  title: titleCtrl.text,
                  quantityLabel: qtyCtrl.text,
                  estimatedPriceMinor: est,
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }
}
