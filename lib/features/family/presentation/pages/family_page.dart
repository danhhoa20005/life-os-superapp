import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/privacy_mask_formatter.dart';
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
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../../transactions/presentation/bloc/transaction_state.dart';
import '../../domain/entities/family_entities.dart';
import '../../domain/usecases/family_usecases.dart';
import '../bloc/family_bloc.dart';

T? _maybeReadFamily<T>(BuildContext context) {
  try {
    return context.read<T>();
  } catch (_) {
    return null;
  }
}

T? _maybeWatchFamily<T>(BuildContext context) {
  try {
    return context.watch<T>();
  } catch (_) {
    return null;
  }
}

({String asset, IconData icon, LifeOsAccentTone tone}) _topicVisual(
  SharedExpenseTopic topic,
) {
  return switch (topic) {
    SharedExpenseTopic.dining => (
      asset: AppAssets.icCatFood,
      icon: Icons.restaurant_rounded,
      tone: LifeOsAccentTone.amber,
    ),
    SharedExpenseTopic.housework => (
      asset: AppAssets.icCatHousework,
      icon: Icons.cleaning_services_rounded,
      tone: LifeOsAccentTone.emerald,
    ),
    SharedExpenseTopic.utilities => (
      asset: AppAssets.icCatUtilities,
      icon: Icons.electric_bolt_rounded,
      tone: LifeOsAccentTone.blue,
    ),
    SharedExpenseTopic.housing => (
      asset: AppAssets.icCatHousing,
      icon: Icons.home_work_rounded,
      tone: LifeOsAccentTone.purple,
    ),
    SharedExpenseTopic.shopping => (
      asset: AppAssets.icCatShopping,
      icon: Icons.shopping_bag_rounded,
      tone: LifeOsAccentTone.emerald,
    ),
    SharedExpenseTopic.travel => (
      asset: AppAssets.icLifeSocialTravel,
      icon: Icons.luggage_outlined,
      tone: LifeOsAccentTone.blue,
    ),
    SharedExpenseTopic.other => (
      asset: AppAssets.icQuickSplit,
      icon: Icons.receipt_long_rounded,
      tone: LifeOsAccentTone.neutral,
    ),
  };
}

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
        if (state.selectedFamilyId != null &&
            state.selectedFamilyId != user.activeFamilyId) {
          context.read<AuthBloc>().add(
            AuthActiveFamilyChanged(state.selectedFamilyId!),
          );
        }
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
        length: 4,
        child: Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  LifeOsTopBrandHeader(
                    title: 'Gia đình',
                    extraBrandActions: [
                      LifeOsHeaderCircleButton(
                        icon: Icons.mic_rounded,
                        tooltip: 'Chia tiền bằng giọng nói',
                        onTap: () => showVoiceSmartCaptureSheet(
                          context,
                          autoStartListening: true,
                        ),
                      ),
                      LifeOsHeaderCircleButton(
                        icon: Icons.group_add_outlined,
                        tooltip: 'Nhập mã mời',
                        onTap: () => _showJoinFamilyDialog(
                          context,
                          user.id,
                          user.fullName,
                        ),
                      ),
                    ],
                    trailingAction: BlocBuilder<FamilyBloc, FamilyState>(
                      buildWhen: (p, c) => p.isSubmitting != c.isSubmitting,
                      builder: (context, famState) => FilledButton.icon(
                        key: const Key('open_create_space_button'),
                        onPressed: famState.isSubmitting
                            ? null
                            : () => _showCreateFamilyDialog(
                                context,
                                user.id,
                                user.fullName,
                              ),
                        icon: const Icon(Icons.add_home_outlined, size: 18),
                        label: const Text('Tạo nhóm'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: BlocBuilder<FamilyBloc, FamilyState>(
                      builder: (context, state) {
                        final family = state.activeFamily;
                        if (family == null) {
                          return _HouseholdAndAssetsHubView(
                            showSoloGroupInviteCard: true,
                            onCreateGroup: () => _showCreateFamilyDialog(
                              context,
                              user.id,
                              user.fullName,
                            ),
                            onJoinGroup: () => _showJoinFamilyDialog(
                              context,
                              user.id,
                              user.fullName,
                            ),
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
                                  constraints: const BoxConstraints(
                                    maxWidth: AppSpacing.maxContentWidth,
                                  ),
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: family.id,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Chuyển không gian cộng tác đang xem',
                                      isDense: true,
                                    ),
                                    items: state.families
                                        .map(
                                          (f) => DropdownMenuItem(
                                            value: f.id,
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                '${f.name} · ${f.spaceType.displayLabel}',
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (nextId) {
                                      if (nextId != null) {
                                        context.read<FamilyBloc>().add(
                                          FamilyShoppingWatchRequested(nextId),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                            const ProPillTabContainer(
                              tabBar: TabBar(
                                labelPadding: EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                tabs: [
                                  Tab(
                                    key: Key('family_split_tab'),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Chia tiền'),
                                    ),
                                  ),
                                  Tab(
                                    key: Key('family_assets_life_tab'),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Tiện ích nhà'),
                                    ),
                                  ),
                                  Tab(
                                    key: Key('family_members_tab'),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Thành viên'),
                                    ),
                                  ),
                                  Tab(
                                    key: Key('family_shopping_tab'),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Mua sắm'),
                                    ),
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
                                  const _HouseholdAndAssetsHubView(
                                    showSoloGroupInviteCard: false,
                                  ),
                                  _MembersAndGovernanceTabView(
                                    family: family,
                                    state: state,
                                    currentUserId: user.id,
                                    currentUserName: user.fullName,
                                  ),
                                  _SharedShoppingTabView(
                                    family: family,
                                    state: state,
                                    currentUserId: user.id,
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
    final bloc = context.read<FamilyBloc>();
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateFamilyDialog(
        bloc: bloc,
        userId: userId,
        userName: userName,
      ),
    );
  }

  Future<void> _showJoinFamilyDialog(
    BuildContext context,
    String userId,
    String userName,
  ) async {
    final bloc = context.read<FamilyBloc>()
      ..add(const FamilyInvitePreviewCleared());
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (_) => _JoinFamilySheet(
        bloc: bloc,
        userId: userId,
        userName: userName,
      ),
    );
  }
}

class _CreateFamilyDialog extends StatefulWidget {
  const _CreateFamilyDialog({
    required this.bloc,
    required this.userId,
    required this.userName,
  });

  final FamilyBloc bloc;
  final String userId;
  final String userName;

  @override
  State<_CreateFamilyDialog> createState() => _CreateFamilyDialogState();
}

class _CreateFamilyDialogState extends State<_CreateFamilyDialog> {
  final TextEditingController _ctrl = TextEditingController();
  CollaborationSpaceType _selectedType = CollaborationSpaceType.family;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
              initialValue: _selectedType,
              items: CollaborationSpaceType.values
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(t.displayLabel),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedType = v);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Tên gọi không gian'),
            const SizedBox(height: 6),
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                hintText: 'VD: Tổ ấm Minh & Lan / Căn hộ P.802 / Team Đà Lạt',
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
        BlocProvider<FamilyBloc>.value(
          value: widget.bloc,
          child: BlocBuilder<FamilyBloc, FamilyState>(
            buildWhen: (p, c) => p.isSubmitting != c.isSubmitting,
            builder: (_, famState) => FilledButton(
              onPressed: famState.isSubmitting
                  ? null
                  : () {
                      widget.bloc.add(
                        FamilyCreateSubmitted(
                          userId: widget.userId,
                          userName: widget.userName,
                          familyName: _ctrl.text,
                          spaceType: _selectedType,
                        ),
                      );
                      Navigator.of(context).pop();
                    },
              child: const Text('Tạo'),
            ),
          ),
        ),
      ],
    );
  }
}

class _JoinFamilySheet extends StatefulWidget {
  const _JoinFamilySheet({
    required this.bloc,
    required this.userId,
    required this.userName,
  });

  final FamilyBloc bloc;
  final String userId;
  final String userName;

  @override
  State<_JoinFamilySheet> createState() => _JoinFamilySheetState();
}

class _JoinFamilySheetState extends State<_JoinFamilySheet> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<FamilyBloc>.value(
      value: widget.bloc,
      child: BlocBuilder<FamilyBloc, FamilyState>(
        builder: (ctx, famState) {
          final c = TammySemanticColors.of(ctx);
          final preview = famState.previewedInvite;
          final viewInsets = MediaQuery.viewInsetsOf(ctx);

          return LiquidGlassSheetFrame(
            showHandle: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                6,
                18,
                20 + viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const LifeOsIconSquircle(
                          icon: Icons.group_add_outlined,
                          tone: LifeOsAccentTone.emerald,
                          size: 40,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tham gia nhóm được mời',
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
                      key: const Key('join_family_invite_input'),
                      controller: _ctrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Mã mời tham gia',
                        hintText: 'VD: FAM-8K2P9Q',
                        suffixIcon: IconButton(
                          tooltip: 'Dán từ bộ nhớ tạm',
                          icon: const Icon(Icons.content_paste_rounded),
                          onPressed: () async {
                            final clip = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            final raw = clip?.text ?? '';
                            if (raw.trim().isNotEmpty && mounted) {
                              final extracted =
                                  FamilyInviteCodeExtractor.extractCode(raw);
                              _ctrl.text = extracted;
                              widget.bloc.add(
                                FamilyInvitePreviewRequested(extracted),
                              );
                            }
                          },
                        ),
                      ),
                      onChanged: (val) {
                        final extracted =
                            FamilyInviteCodeExtractor.extractCode(val);
                        if (extracted.startsWith('FAM-') &&
                            extracted.length >= 8) {
                          widget.bloc.add(
                            FamilyInvitePreviewRequested(extracted),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('preview_family_invite_button'),
                        onPressed: famState.isPreviewingInvite
                            ? null
                            : () => widget.bloc.add(
                                FamilyInvitePreviewRequested(_ctrl.text),
                              ),
                        icon: famState.isPreviewingInvite
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.verified_outlined, size: 17),
                        label: const Text('Kiểm tra thông tin lời mời'),
                      ),
                    ),
                    if (preview != null) ...[
                      const SizedBox(height: 6),
                      LifeOsMintHeroCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 18,
                                  color: Color(0xFF0B7A2A),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    preview.familyName,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                ),
                                LifeOsStatusPill(
                                  label:
                                      'Còn ${preview.remainingDaysFrom(DateTime.now())} ngày',
                                  tone: LifeOsAccentTone.emerald,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${preview.spaceType.displayLabel} · Mời bởi ${preview.invitedByName}',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 12.4,
                                fontWeight: FontWeight.w600,
                                color: c.textSecondary,
                              ),
                            ),
                            if (preview.isTargetedInvite) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Dành cho: ${preview.inviteeName}',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 12.2,
                                  fontWeight: FontWeight.w700,
                                  color: c.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
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
                            key: const Key('confirm_join_family_button'),
                            onPressed: famState.isSubmitting
                                ? null
                                : () {
                                    widget.bloc.add(
                                      FamilyJoinByCodeSubmitted(
                                        userId: widget.userId,
                                        userName: widget.userName,
                                        inviteCode: _ctrl.text,
                                      ),
                                    );
                                    Navigator.of(ctx).pop();
                                  },
                            icon: const Icon(Icons.login_rounded, size: 18),
                            label: const Text('Tham gia'),
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

class _SplitBillsAndSettlementTabView extends StatefulWidget {
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
  State<_SplitBillsAndSettlementTabView> createState() =>
      _SplitBillsAndSettlementTabViewState();
}

class _SplitBillsAndSettlementTabViewState
    extends State<_SplitBillsAndSettlementTabView> {
  final Set<String> _revealedTransferCodes = <String>{};
  final Set<String> _revealedSettlementIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final family = widget.family;
    final state = widget.state;
    final currentUserId = widget.currentUserId;
    final currentUserName = widget.currentUserName;
    final c = TammySemanticColors.of(context);
    final ledger = state.sharedLedger;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          key: const Key('split_bills_list_view'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.dockClearance,
          ),
          children: [
            // Unified LifeOS "Tổng quan gia đình" Pastel Mint Hero Card (`06_Gia_dinh.png`)
            Builder(
              builder: (context) {
                final taskCount =
                    _maybeWatchFamily<TaskBloc>(context)?.state.tasks.length ??
                    0;
                final eventCount =
                    _maybeWatchFamily<CalendarBloc>(
                      context,
                    )?.state.events.length ??
                    0;
                final totalFunds =
                    _maybeWatchFamily<BudgetBloc>(context)?.state.funds.fold<int>(
                      0,
                      (s, f) => s + f.balanceMinor,
                    ) ??
                    0;
                final displayFund = totalFunds > 0
                    ? totalFunds
                    : ledger.totalSharedSpendMinor;

                return LifeOsMintHeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.groups_outlined,
                                size: 20,
                                color: c.primary,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  family.name,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 17,
                                    height: 1.2,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const LifeOsStatusPill(
                            icon: Icons.verified_user_outlined,
                            label: 'Chia sẻ an toàn',
                            tone: LifeOsAccentTone.emerald,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Builder(
                        builder: (context) {
                          final activeInvites = family.activePendingInvites();
                          return Row(
                            children: [
                              LifeOsAvatarStack(
                                names: family.members
                                    .map((m) => m.fullName)
                                    .toList(),
                                pendingNames: activeInvites
                                    .map((i) => i.displayInviteeTitle)
                                    .toList(),
                                onAddTap: family.isManager(currentUserId)
                                    ? () => showFamilyInviteMemberSheet(
                                        context,
                                        family: family,
                                        currentUserId: currentUserId,
                                        currentUserName: currentUserName,
                                      )
                                    : null,
                                radius: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  activeInvites.isEmpty
                                      ? '${family.members.length} thành viên cùng quản lý'
                                      : '${family.members.length} thành viên · ${activeInvites.length} lời mời đang chờ',
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 12.2,
                                    fontWeight: FontWeight.w600,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const Key('open_add_split_bill_button'),
                            onPressed: state.isSubmitting
                                ? null
                                : () => showSharedBillSplitSheet(
                                    context,
                                    family: family,
                                    currentUserId: currentUserId,
                                    currentUserName: currentUserName,
                                  ),
                            icon: const Icon(
                              Icons.call_split_rounded,
                              size: 18,
                            ),
                            label: const Text('Chia khoản mới'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.push('/family-funds'),
                            icon: const Icon(Icons.savings_outlined, size: 17),
                            label: const Text('Quỹ chung'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LifeOsDetailsDiscloseSection(
                        toggleKey: const Key(
                          'family_split_hero_details_toggle',
                        ),
                        label: 'Chi tiết sổ chung',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                LifeOsStatusPill(
                                  icon: Icons.receipt_long_outlined,
                                  label:
                                      'Tổng chi: ${VndAmount.format(ledger.totalSharedSpendMinor)}',
                                  tone: LifeOsAccentTone.emerald,
                                ),
                                LifeOsStatusPill(
                                  icon: Icons.layers_outlined,
                                  label:
                                      '${state.sharedBills.length} khoản chia',
                                  tone: LifeOsAccentTone.blue,
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            IntrinsicHeight(
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: InkWell(
                                      onTap: () => context.push('/tasks-board'),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Việc chung',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              '$taskCount',
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
                                        ],
                                      ),
                                    ),
                                  ),
                                  VerticalDivider(
                                    width: 12,
                                    color: c.separator,
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: InkWell(
                                      onTap: () => context.go('/planning'),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Lịch chung',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              '$eventCount',
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
                                        ],
                                      ),
                                    ),
                                  ),
                                  VerticalDivider(
                                    width: 12,
                                    color: c.separator,
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: InkWell(
                                      onTap: () =>
                                          context.push('/family-funds'),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Quỹ & Chi chung',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: LifeOsTruthfulNumericText(
                                              formattedValue: VndAmount.format(
                                                displayFund,
                                              ),
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
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
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => context.push('/assets'),
                                  icon: const Icon(
                                    Icons.directions_car_outlined,
                                    size: 17,
                                  ),
                                  label: const Text('Xe & Hóa đơn'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      context.push('/family-documents'),
                                  icon: const Icon(
                                    Icons.folder_open_rounded,
                                    size: 17,
                                  ),
                                  label: const Text('Tài liệu'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const LifeOsSectionHeader(title: 'Cân đối chi tiêu thành viên'),
            LifeOsSoftCard(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: ledger.memberBalances.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        'Chưa có số liệu cân đối chi tiêu giữa các thành viên.',
                        style: TextStyle(fontSize: 13, color: c.textSecondary),
                      ),
                    )
                  : Column(
                      children: [
                        for (
                          var i = 0;
                          i < ledger.memberBalances.length;
                          i++
                        ) ...[
                          if (i > 0) const Divider(height: 14),
                          Builder(
                            builder: (_) {
                              final mb = ledger.memberBalances[i];
                              final isPositive = mb.netBalanceMinor > 0;
                              final isNegative = mb.netBalanceMinor < 0;
                              final statusColor = isPositive
                                  ? c.success
                                  : (isNegative ? c.error : c.textSecondary);
                              final statusLabel = isPositive
                                  ? 'Nhận lại ${VndAmount.format(mb.netBalanceMinor)}'
                                  : isNegative
                                  ? 'Cần trả ${VndAmount.format(mb.netBalanceMinor.abs())}'
                                  : 'Đã cân bằng';

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 6,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: c.primarySubtle,
                                      child: Text(
                                        mb.fullName.isNotEmpty
                                            ? mb.fullName[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: c.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            alignment:
                                                WrapAlignment.spaceBetween,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                mb.fullName,
                                                softWrap: true,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              Text(
                                                statusLabel,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: statusColor,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'Đã trả: ${VndAmount.format(mb.totalPaidMinor)} · Phần chia: ${VndAmount.format(mb.totalOwedMinor)}',
                                            softWrap: true,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
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
                              );
                            },
                          ),
                        ],
                      ],
                    ),
            ),

            const LifeOsSectionHeader(
              title: 'Gợi ý thanh toán nhanh',
              tone: LifeOsAccentTone.amber,
            ),
            if (ledger.suggestedTransfers.isEmpty)
              LifeOsSoftCard(
                child: Row(
                  children: [
                    const BananaGlassIcon(
                      assetPath: AppAssets.icQuickSplit,
                      fallbackIcon: Icons.verified_outlined,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mọi khoản chi chung đã cân bằng',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.2,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Không có khoản chênh lệch nào cần chuyển trả.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              ...ledger.suggestedTransfers.map((tr) {
                final transferKey =
                    '${tr.fromUserId}_${tr.toUserId}_${tr.amountMinor}';
                final isRevealed = _revealedTransferCodes.contains(transferKey);
                final maskedCode = PrivacyMaskFormatter.maskCode(
                  tr.sePayTransferCode,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LifeOsSoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const BananaGlassIcon(
                              assetPath: AppAssets.icQuickSplit,
                              fallbackIcon: Icons.swap_horiz_rounded,
                              size: 40,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${tr.fromUserName} → ${tr.toUserName}',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    VndAmount.format(tr.amountMinor),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: c.primary,
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
                        const SizedBox(height: 8),
                        InkWell(
                          key: Key('toggle_transfer_code_$transferKey'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() {
                            if (isRevealed) {
                              _revealedTransferCodes.remove(transferKey);
                            } else {
                              _revealedTransferCodes.add(transferKey);
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: c.primarySubtle,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Nội dung CK: ${isRevealed ? tr.sePayTransferCode : maskedCode}',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 12.2,
                                      fontWeight: FontWeight.w700,
                                      color: c.primary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  isRevealed
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 16,
                                  color: c.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: state.isSubmitting
                                  ? null
                                  : () {
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
                                                paymentCode:
                                                    tr.sePayTransferCode,
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                              icon: const Icon(
                                Icons.qr_code_2_rounded,
                                size: 16,
                              ),
                              label: const Text('Mã QR'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: tr.sePayTransferCode),
                                );
                                LifeOsTopToast.show(
                                  context,
                                  'Đã sao chép mã chuyển khoản.',
                                  kind: LifeOsToastKind.success,
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 15),
                              label: const Text('Copy mã'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: state.isSubmitting
                                  ? null
                                  : () async {
                                      final confirmed =
                                          await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text(
                                                'Xác nhận đã tất toán?',
                                              ),
                                              content: Text(
                                                'Ghi nhận ${tr.fromUserName} đã chuyển ${VndAmount.format(tr.amountMinor)} cho ${tr.toUserName}?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(
                                                        ctx,
                                                      ).pop(false),
                                                  child: const Text('Hủy'),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.of(
                                                        ctx,
                                                      ).pop(true),
                                                  child: const Text(
                                                    'Xác nhận tất toán',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ) ??
                                          false;
                                      if (!confirmed || !context.mounted) {
                                        return;
                                      }
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
                              icon: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 16,
                              ),
                              label: const Text('Ghi nhận đã tất toán'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),

            LifeOsSectionHeader(
              title: 'Sổ Khoản chi Chung (${state.sharedBills.length})',
              tone: LifeOsAccentTone.blue,
            ),
            if (state.sharedBills.isEmpty)
              LifeOsSoftCard(
                child: Column(
                  children: [
                    const BananaGlassIcon(
                      assetPath: AppAssets.icCatFood,
                      fallbackIcon: Icons.receipt_long_rounded,
                      size: 48,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Chưa có khoản chi chung nào',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ghi lại hóa đơn ăn uống, điện nước hoặc đi chợ chung để hệ thống tự tính phần chia minh bạch.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: state.isSubmitting
                          ? null
                          : () => showSharedBillSplitSheet(
                              context,
                              family: family,
                              currentUserId: currentUserId,
                              currentUserName: currentUserName,
                            ),
                      icon: const Icon(Icons.call_split_rounded, size: 17),
                      label: const Text('Tạo khoản chia đầu tiên'),
                    ),
                  ],
                ),
              )
            else
              ...state.sharedBills.map((bill) {
                final visual = _topicVisual(bill.topic);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LifeOsSoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BananaGlassIcon(
                              assetPath: visual.asset,
                              fallbackIcon: visual.icon,
                              size: 42,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bill.title,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${bill.topic.displayLabel} · Trả trước: ${bill.paidByName} · ${bill.splitMethod.displayLabel}',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 12.2,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  VndAmount.format(bill.totalAmountMinor),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
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
                        const SizedBox(height: 10),
                        LifeOsDetailsDiscloseSection(
                          label: 'Chi tiết phần chia',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (bill.choreOrTaskNote != null &&
                                  bill.choreOrTaskNote!.isNotEmpty) ...[
                                Text(
                                  'Gắn việc nhà / ghi chú: ${bill.choreOrTaskNote}',
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 12.2,
                                    color: c.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: bill.sharesByUserId.entries
                                    .map(
                                      (e) => LifeOsStatusPill(
                                        label:
                                            '${bill.participantNames[e.key] ?? 'TV'}: ${VndAmount.format(e.value)}',
                                        tone: LifeOsAccentTone.neutral,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

            if (state.settlements.isNotEmpty) ...[
              LifeOsSectionHeader(
                title: 'Lịch sử Tất toán (${state.settlements.length})',
                tone: LifeOsAccentTone.emerald,
              ),
              ...state.settlements.take(10).map((st) {
                final isRevealed = _revealedSettlementIds.contains(st.id);
                final displayCode = isRevealed
                    ? st.paymentCode
                    : PrivacyMaskFormatter.maskCode(st.paymentCode);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LifeOsSoftCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const LifeOsIconSquircle(
                              icon: Icons.verified_rounded,
                              tone: LifeOsAccentTone.emerald,
                              size: 36,
                              iconSize: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${st.fromUserName} đã trả ${st.toUserName}',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  InkWell(
                                    key: Key('toggle_settlement_code_${st.id}'),
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () => setState(() {
                                      if (isRevealed) {
                                        _revealedSettlementIds.remove(st.id);
                                      } else {
                                        _revealedSettlementIds.add(st.id);
                                      }
                                    }),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            'Mã đối soát: $displayCode',
                                            softWrap: true,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: c.textSecondary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Icon(
                                          isRevealed
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          size: 14,
                                          color: c.textSecondary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 118),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  VndAmount.format(st.amountMinor),
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: c.success,
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
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showSharedBillSplitSheet(
  BuildContext context, {
  required FamilyEntity family,
  required String currentUserId,
  required String currentUserName,
  String initialTitle = '',
  int? initialAmountMinor,
  SharedExpenseTopic initialTopic = SharedExpenseTopic.dining,
  String initialChoreNote = '',
}) async {
  final bloc = context.read<FamilyBloc>();
  final txListBloc = _maybeReadFamily<TransactionListBloc>(context);
  final txActionBloc = _maybeReadFamily<TransactionActionBloc>(context);
  final wallets = txListBloc?.state.wallets ?? const <WalletEntity>[];

  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (_) => _SharedBillSplitSheet(
      bloc: bloc,
      txActionBloc: txActionBloc,
      wallets: wallets,
      family: family,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      initialTitle: initialTitle,
      initialAmountMinor: initialAmountMinor,
      initialTopic: initialTopic,
      initialChoreNote: initialChoreNote,
    ),
  );
}

class _SharedBillSplitSheet extends StatefulWidget {
  const _SharedBillSplitSheet({
    required this.bloc,
    required this.txActionBloc,
    required this.wallets,
    required this.family,
    required this.currentUserId,
    required this.currentUserName,
    required this.initialTitle,
    required this.initialAmountMinor,
    required this.initialTopic,
    required this.initialChoreNote,
  });

  final FamilyBloc bloc;
  final TransactionActionBloc? txActionBloc;
  final List<WalletEntity> wallets;
  final FamilyEntity family;
  final String currentUserId;
  final String currentUserName;
  final String initialTitle;
  final int? initialAmountMinor;
  final SharedExpenseTopic initialTopic;
  final String initialChoreNote;

  @override
  State<_SharedBillSplitSheet> createState() => _SharedBillSplitSheetState();
}

class _SharedBillSplitSheetState extends State<_SharedBillSplitSheet> {
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.initialTitle,
  );
  late final TextEditingController _totalCtrl = TextEditingController(
    text: (widget.initialAmountMinor != null && widget.initialAmountMinor! > 0)
        ? '${widget.initialAmountMinor}'
        : '',
  );
  late final TextEditingController _choreCtrl = TextEditingController(
    text: widget.initialChoreNote,
  );
  late final Map<String, TextEditingController> _perMemberCtrls =
      <String, TextEditingController>{
        for (final m in widget.family.members)
          m.userId: TextEditingController(text: '1'),
      };

  late SharedExpenseTopic _topic = widget.initialTopic;
  SplitMethod _method = SplitMethod.equal;
  late String _payerId =
      widget.family.members.any((m) => m.userId == widget.currentUserId)
          ? widget.currentUserId
          : widget.family.members.first.userId;
  late final Set<String> _selectedIds = <String>{
    for (final m in widget.family.members) m.userId,
  };
  late String? _selectedWalletId =
      widget.wallets.isNotEmpty ? widget.wallets.first.id : null;
  bool _recordToPersonalWallet = false;
  bool _isSubmittingLocal = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _totalCtrl.dispose();
    _choreCtrl.dispose();
    for (final ctrl in _perMemberCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final family = widget.family;
    final wallets = widget.wallets;
    return BlocProvider<FamilyBloc>.value(
      value: widget.bloc,
      child: BlocBuilder<FamilyBloc, FamilyState>(
        buildWhen: (p, n) => p.isSubmitting != n.isSubmitting,
        builder: (ctx, famState) {
          final c = TammySemanticColors.of(ctx);
          final viewInsets = MediaQuery.viewInsetsOf(ctx);
          final maxHeight = MediaQuery.sizeOf(ctx).height * 0.88;
          final isBusy = famState.isSubmitting || _isSubmittingLocal;
          final isSelfPayer = _payerId == widget.currentUserId;
          final canRecordWallet =
              isSelfPayer && wallets.isNotEmpty && widget.txActionBloc != null;

          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: LiquidGlassSheetFrame(
              showHandle: true,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  6,
                  18,
                  18 + viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        BananaGlassIcon(
                          assetPath: _topicVisual(_topic).asset,
                          fallbackIcon: Icons.call_split_rounded,
                          size: 40,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Chia Khoản chi Chung',
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
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Nhóm khoản chung'),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<SharedExpenseTopic>(
                              isExpanded: true,
                              initialValue: _topic,
                              items: SharedExpenseTopic.values
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(t.displayLabel),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: isBusy
                                  ? null
                                  : (v) {
                                      if (v != null) {
                                        setState(() => _topic = v);
                                      }
                                    },
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            const Text('Nội dung chi tiêu'),
                            const SizedBox(height: 6),
                            TextField(
                              key: const Key('split_bill_title_input'),
                              controller: _titleCtrl,
                              decoration: const InputDecoration(
                                hintText:
                                    'VD: Lẩu cuối tuần / Mua nước lau sàn',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            const Text('Tổng số tiền (VND)'),
                            const SizedBox(height: 6),
                            TextField(
                              key: const Key('split_bill_amount_input'),
                              controller: _totalCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: '300000',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            const Text('Ai là người ứng tiền trả trước?'),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _payerId,
                              items: family.members
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m.userId,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(m.fullName),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: isBusy
                                  ? null
                                  : (v) {
                                      if (v != null) {
                                        setState(() => _payerId = v);
                                      }
                                    },
                            ),
                            if (isSelfPayer) ...[
                              const SizedBox(height: AppSpacing.xs),
                              SwitchListTile(
                                key: const Key(
                                  'split_bill_record_wallet_switch',
                                ),
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Đồng thời ghi vào Ví cá nhân',
                                ),
                                subtitle: Text(
                                  canRecordWallet
                                      ? 'Trừ khoản ứng trước này vào ví cá nhân của bạn'
                                      : 'Chưa có ví cá nhân để ghi giao dịch',
                                ),
                                value:
                                    _recordToPersonalWallet && canRecordWallet,
                                onChanged: canRecordWallet && !isBusy
                                    ? (v) => setState(
                                        () => _recordToPersonalWallet = v,
                                      )
                                    : null,
                              ),
                              if (_recordToPersonalWallet &&
                                  canRecordWallet &&
                                  wallets.length > 1) ...[
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _selectedWalletId,
                                  decoration: const InputDecoration(
                                    labelText: 'Chọn ví thanh toán',
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
                                  onChanged: isBusy
                                      ? null
                                      : (v) => setState(
                                          () => _selectedWalletId = v,
                                        ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                              ],
                            ],
                            const SizedBox(height: AppSpacing.sm),
                            const Text('Phương thức chia tiền'),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<SplitMethod>(
                              isExpanded: true,
                              initialValue: _method,
                              items: SplitMethod.values
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(m.displayLabel),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: isBusy
                                  ? null
                                  : (v) {
                                      if (v != null) {
                                        setState(() {
                                          _method = v;
                                          if (_method ==
                                                  SplitMethod.percentage &&
                                              _selectedIds.isNotEmpty) {
                                            final basePct =
                                                100 ~/ _selectedIds.length;
                                            var rem =
                                                100 % _selectedIds.length;
                                            for (final uid in _selectedIds) {
                                              final add = rem > 0 ? 1 : 0;
                                              if (rem > 0) rem -= 1;
                                              _perMemberCtrls[uid]?.text =
                                                  '${basePct + add}';
                                            }
                                          } else if (_method ==
                                              SplitMethod.shares) {
                                            for (final uid in _selectedIds) {
                                              _perMemberCtrls[uid]?.text = '1';
                                            }
                                          }
                                        });
                                      }
                                    },
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            const Text('Thành viên tham gia'),
                            ...family.members.map((m) {
                              final checked = _selectedIds.contains(m.userId);
                              return Column(
                                children: [
                                  CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    value: checked,
                                    title: Text(m.fullName),
                                    onChanged: isBusy
                                        ? null
                                        : (val) {
                                            setState(() {
                                              if (val == true) {
                                                _selectedIds.add(m.userId);
                                              } else if (_selectedIds.length >
                                                  1) {
                                                _selectedIds.remove(m.userId);
                                              }
                                            });
                                          },
                                  ),
                                  if (checked && _method != SplitMethod.equal)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: TextField(
                                        controller: _perMemberCtrls[m.userId],
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          labelText: switch (_method) {
                                            SplitMethod.percentage =>
                                              'Tỷ lệ % của ${m.fullName}',
                                            SplitMethod.shares =>
                                              'Số phần / hệ số của ${m.fullName}',
                                            SplitMethod.exact =>
                                              'Số tiền VND của ${m.fullName}',
                                            SplitMethod.equal => '',
                                          },
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            }),
                            const SizedBox(height: AppSpacing.xs),
                            const Text(
                              'Gắn ghi chú Việc nhà / Nhiệm vụ (tùy chọn)',
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _choreCtrl,
                              decoration: const InputDecoration(
                                hintText: 'VD: Ca trực nhật dọn bếp tuần này',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isBusy
                                ? null
                                : () => Navigator.of(ctx).pop(),
                            child: const Text('Hủy'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            key: const Key('submit_split_bill_button'),
                            onPressed: isBusy
                                ? null
                                : () async {
                                    final title = _titleCtrl.text.trim();
                                    final total =
                                        VndAmount.tryParseInput(
                                          _totalCtrl.text,
                                        ) ??
                                        0;
                                    if (title.length < 2 || total <= 0) {
                                      LifeOsTopToast.show(
                                        ctx,
                                        'Vui lòng nhập nội dung (>= 2 ký tự) và tổng tiền > 0 ₫.',
                                        kind: LifeOsToastKind.warning,
                                      );
                                      return;
                                    }
                                    final payerMember = family.members
                                        .firstWhere(
                                          (m) => m.userId == _payerId,
                                          orElse: () => FamilyMemberInfo(
                                            userId: widget.currentUserId,
                                            fullName: widget.currentUserName,
                                            role: HouseholdRole.member,
                                          ),
                                        );
                                    final rawInputs = <String, int>{};
                                    for (final uid in _selectedIds) {
                                      final rawTxt =
                                          _perMemberCtrls[uid]?.text ?? '0';
                                      rawInputs[uid] =
                                          _method == SplitMethod.exact
                                          ? (VndAmount.tryParseInput(rawTxt) ??
                                                0)
                                          : (int.tryParse(rawTxt.trim()) ?? 0);
                                    }
                                    final namesMap = <String, String>{
                                      for (final m in family.members)
                                        m.userId: m.fullName,
                                    };

                                    if (_recordToPersonalWallet &&
                                        canRecordWallet &&
                                        _selectedWalletId != null) {
                                      setState(() => _isSubmittingLocal = true);
                                      final categoryForTopic = switch (_topic) {
                                        SharedExpenseTopic.dining => 'Ăn uống',
                                        SharedExpenseTopic.housework =>
                                          'Việc nhà & Gia dụng',
                                        SharedExpenseTopic.utilities =>
                                          'Điện/Nước/Internet',
                                        SharedExpenseTopic.housing =>
                                          'Nhà cửa & Thuê nhà',
                                        SharedExpenseTopic.shopping =>
                                          'Chợ & Mua sắm',
                                        SharedExpenseTopic.travel ||
                                        SharedExpenseTopic.other =>
                                          'Chi tiêu khác',
                                      };
                                      final txRes = await widget.txActionBloc!
                                          .submitAndAwaitCreate(
                                            TransactionCreateSubmitted(
                                              operationId: const Uuid().v4(),
                                              userId: widget.currentUserId,
                                              walletId: _selectedWalletId!,
                                              categoryName: categoryForTopic,
                                              kind: TransactionKind.expense,
                                              amountMinor: total,
                                              merchant: title,
                                              note:
                                                  'Chia tiền nhóm ${family.name}',
                                              occurredAt: DateTime.now(),
                                            ),
                                          );
                                      if (!ctx.mounted) return;
                                      if (txRes.status !=
                                          ActionStatus.success) {
                                        setState(
                                          () => _isSubmittingLocal = false,
                                        );
                                        LifeOsTopToast.show(
                                          ctx,
                                          txRes.failure?.message ??
                                              'Không thể ghi giao dịch vào Ví cá nhân.',
                                          kind: LifeOsToastKind.error,
                                        );
                                        return;
                                      }
                                    }

                                    widget.bloc.add(
                                      SharedBillSplitCreated(
                                        CreateSharedBillSplitParams(
                                          familyId: family.id,
                                          title: title,
                                          topic: _topic,
                                          paidByUserId: payerMember.userId,
                                          paidByName: payerMember.fullName,
                                          totalAmountMinor: total,
                                          splitMethod: _method,
                                          participantIds: _selectedIds.toList(),
                                          participantNames: namesMap,
                                          rawInputValuesByUserId: rawInputs,
                                          choreOrTaskNote: _choreCtrl.text,
                                        ),
                                      ),
                                    );
                                    if (ctx.mounted) {
                                      Navigator.of(ctx).pop();
                                    }
                                  },
                            child: isBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Lưu & Tính chia'),
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

String _buildFamilyInviteShareText({
  required String familyName,
  required String inviteCode,
  String? inviteeName,
}) {
  final greeting = (inviteeName != null && inviteeName.trim().isNotEmpty)
      ? 'Chào ${inviteeName.trim()}, mời bạn'
      : 'Mời bạn';
  return '$greeting tham gia nhóm "$familyName" trên ứng dụng LifeOS. Mở mục Gia đình → Nhập mã mời: $inviteCode (hiệu lực 7 ngày).';
}

Future<void> showFamilyInviteMemberSheet(
  BuildContext context, {
  required FamilyEntity family,
  required String currentUserId,
  required String currentUserName,
}) async {
  final bloc = context.read<FamilyBloc>();
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (_) => _FamilyInviteMemberSheet(
      bloc: bloc,
      family: family,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
    ),
  );
}

class _FamilyInviteMemberSheet extends StatefulWidget {
  const _FamilyInviteMemberSheet({
    required this.bloc,
    required this.family,
    required this.currentUserId,
    required this.currentUserName,
  });

  final FamilyBloc bloc;
  final FamilyEntity family;
  final String currentUserId;
  final String currentUserName;

  @override
  State<_FamilyInviteMemberSheet> createState() =>
      _FamilyInviteMemberSheetState();
}

class _FamilyInviteMemberSheetState extends State<_FamilyInviteMemberSheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _contactCtrl = TextEditingController();
  bool _revealLatestCode = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final family = widget.family;
    return BlocProvider<FamilyBloc>.value(
      value: widget.bloc,
      child: BlocBuilder<FamilyBloc, FamilyState>(
        builder: (ctx, famState) {
          final c = TammySemanticColors.of(ctx);
          final viewInsets = MediaQuery.viewInsetsOf(ctx);
          final updatedFamily =
              famState.families
                  .where((f) => f.id == family.id)
                  .firstOrNull ??
              family;
          final latestInvite = updatedFamily
              .activePendingInvites()
              .where((i) => i.inviteCode == famState.latestInviteCode)
              .firstOrNull;
          final rawLatestCode = famState.latestInviteCode;
          final displayLatestCode = rawLatestCode == null
              ? null
              : (_revealLatestCode
                    ? rawLatestCode
                    : PrivacyMaskFormatter.maskCode(rawLatestCode));

          return LiquidGlassSheetFrame(
            showHandle: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                6,
                18,
                20 + viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const LifeOsIconSquircle(
                          icon: Icons.group_add_outlined,
                          tone: LifeOsAccentTone.emerald,
                          size: 40,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Mời thành viên vào "${family.name}"',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('invite_member_name_input'),
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Tên thành viên được mời (khuyên dùng)',
                        hintText: 'VD: Trần Lan / Minh Anh',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('invite_member_contact_input'),
                      controller: _contactCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại hoặc Email (tùy chọn)',
                        hintText: 'VD: 0909 123 456 hoặc lan@gmail.com',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('submit_create_member_invite_button'),
                      onPressed: famState.isSubmitting
                          ? null
                          : () {
                              setState(() => _revealLatestCode = false);
                              widget.bloc.add(
                                FamilyInviteGenerated(
                                  userId: widget.currentUserId,
                                  familyId: family.id,
                                  familyName: family.name,
                                  spaceType: family.spaceType,
                                  invitedByName: widget.currentUserName,
                                  inviteeName: _nameCtrl.text,
                                  inviteeContact: _contactCtrl.text,
                                ),
                              );
                            },
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Tạo lời mời 7 ngày'),
                    ),
                    if (rawLatestCode != null && displayLatestCode != null) ...[
                      const SizedBox(height: 14),
                      LifeOsMintHeroCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    latestInvite != null &&
                                            latestInvite.isTargetedInvite
                                        ? 'Lời mời dành cho ${latestInvite.inviteeName}'
                                        : 'Mã mời sẵn sàng gửi (7 ngày)',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                ),
                                const LifeOsStatusPill(
                                  label: 'Đang chờ',
                                  tone: LifeOsAccentTone.amber,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    displayLatestCode,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                      color: c.primary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: const Key(
                                    'toggle_latest_invite_code_btn',
                                  ),
                                  tooltip: _revealLatestCode
                                      ? 'Ẩn mã mời'
                                      : 'Hiện mã mời',
                                  onPressed: () => setState(
                                    () =>
                                        _revealLatestCode = !_revealLatestCode,
                                  ),
                                  icon: Icon(
                                    _revealLatestCode
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: c.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  key: const Key('copy_invite_code_btn'),
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(text: rawLatestCode),
                                    );
                                    LifeOsTopToast.show(
                                      ctx,
                                      'Đã sao chép mã mời tham gia nhóm.',
                                      kind: LifeOsToastKind.success,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Sao chép mã'),
                                ),
                                OutlinedButton.icon(
                                  key: const Key(
                                    'copy_full_invite_message_btn',
                                  ),
                                  onPressed: () {
                                    final msg = _buildFamilyInviteShareText(
                                      familyName: family.name,
                                      inviteCode: rawLatestCode,
                                      inviteeName: latestInvite?.inviteeName,
                                    );
                                    Clipboard.setData(ClipboardData(text: msg));
                                    LifeOsTopToast.show(
                                      ctx,
                                      'Đã sao chép lời mời đầy đủ để gửi Zalo / Tin nhắn.',
                                      kind: LifeOsToastKind.success,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Chép tin nhắn mời'),
                                ),
                              ],
                            ),
                          ],
                        ),
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
  }
}

class _MembersAndGovernanceTabView extends StatefulWidget {
  final FamilyEntity family;
  final FamilyState state;
  final String currentUserId;
  final String currentUserName;

  const _MembersAndGovernanceTabView({
    required this.family,
    required this.state,
    required this.currentUserId,
    required this.currentUserName,
  });

  @override
  State<_MembersAndGovernanceTabView> createState() =>
      _MembersAndGovernanceTabViewState();
}

class _MembersAndGovernanceTabViewState
    extends State<_MembersAndGovernanceTabView> {
  final Set<String> _revealedInviteCodes = <String>{};

  @override
  Widget build(BuildContext context) {
    final family = widget.family;
    final state = widget.state;
    final currentUserId = widget.currentUserId;
    final currentUserName = widget.currentUserName;
    final c = TammySemanticColors.of(context);
    final now = DateTime.now();
    final isManager = family.isManager(currentUserId);
    final isOwner = family.isOwnerUser(currentUserId);
    final activeInvites = family.activePendingInvites(now);
    final balanceByUid = <String, MemberNetBalance>{
      for (final b in state.sharedLedger.memberBalances) b.userId: b,
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          key: const Key('members_list_view'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.dockClearance,
          ),
          children: [
            // 1. Group Governance & Quick Invite Hero Card
            LifeOsMintHeroCard(
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
                        softWrap: true,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SemanticStatusBadge(
                        kind: SemanticStatusKind.info,
                        label:
                            '${family.spaceType.displayLabel} · ${family.roleOf(currentUserId).displayLabel}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (isManager)
                        FilledButton.icon(
                          key: const Key('open_invite_member_sheet_button'),
                          onPressed: () => showFamilyInviteMemberSheet(
                            context,
                            family: family,
                            currentUserId: currentUserId,
                            currentUserName: currentUserName,
                          ),
                          icon: const Icon(
                            Icons.person_add_alt_1_rounded,
                            size: 18,
                          ),
                          label: const Text('Mời thành viên'),
                        ),
                      if (isManager)
                        OutlinedButton.icon(
                          key: const Key('quick_generate_invite_code_button'),
                          onPressed: state.isSubmitting
                              ? null
                              : () => context.read<FamilyBloc>().add(
                                  FamilyInviteGenerated(
                                    userId: currentUserId,
                                    familyId: family.id,
                                    familyName: family.name,
                                    spaceType: family.spaceType,
                                    invitedByName: currentUserName,
                                  ),
                                ),
                          icon: const Icon(Icons.qr_code_rounded, size: 18),
                          label: const Text('Tạo mã mời 7 ngày'),
                        ),
                      OutlinedButton.icon(
                        onPressed: state.isSubmitting
                            ? null
                            : () async {
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
                ],
              ),
            ),

            // 2. Pending Invited Members Section ("Thành viên được mời · Đang chờ")
            LifeOsSectionHeader(
              title: 'Thành viên được mời (${activeInvites.length})',
              tone: LifeOsAccentTone.amber,
            ),
            if (activeInvites.isEmpty)
              LifeOsSoftCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const LifeOsIconSquircle(
                      icon: Icons.group_add_outlined,
                      tone: LifeOsAccentTone.amber,
                      size: 38,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Chưa có lời mời đang chờ xác nhận.',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12.6,
                          height: 1.32,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...activeInvites.map((inv) {
                final daysLeft = inv.remainingDaysFrom(now);
                final isRevealed = _revealedInviteCodes.contains(
                  inv.inviteCode,
                );
                final displayCode = isRevealed
                    ? inv.inviteCode
                    : PrivacyMaskFormatter.maskCode(inv.inviteCode);
                final displayContact =
                    (inv.inviteeContact != null &&
                        inv.inviteeContact!.isNotEmpty)
                    ? (isRevealed
                          ? inv.inviteeContact!
                          : PrivacyMaskFormatter.maskContact(
                              inv.inviteeContact!,
                            ))
                    : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LifeOsSoftCard(
                    key: Key('pending_invite_card_${inv.inviteCode}'),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: c.warningSubtle,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: c.warning,
                                  width: 1.4,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                inv.isTargetedInvite
                                    ? Icons.person_add_alt_1_rounded
                                    : Icons.link_rounded,
                                size: 19,
                                color: c.warning,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        inv.displayInviteeTitle,
                                        softWrap: true,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SemanticStatusBadge(
                                        kind: SemanticStatusKind.warning,
                                        label: 'Đang chờ',
                                      ),
                                    ],
                                  ),
                                  if (displayContact.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      displayContact,
                                      softWrap: true,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 3),
                                  Text(
                                    'Mời bởi ${inv.invitedByName} · Còn hạn $daysLeft ngày',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 11.8,
                                      color: c.textSecondary,
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
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            InkWell(
                              key: Key('toggle_invite_code_${inv.inviteCode}'),
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() {
                                if (isRevealed) {
                                  _revealedInviteCodes.remove(inv.inviteCode);
                                } else {
                                  _revealedInviteCodes.add(inv.inviteCode);
                                }
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: c.primarySubtle,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      displayCode,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                        color: c.primary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Icon(
                                      isRevealed
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 14,
                                      color: c.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: inv.inviteCode),
                                );
                                LifeOsTopToast.show(
                                  context,
                                  'Đã sao chép mã mời tham gia nhóm.',
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 15),
                              label: const Text('Sao chép mã'),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () {
                                final msg = _buildFamilyInviteShareText(
                                  familyName: family.name,
                                  inviteCode: inv.inviteCode,
                                  inviteeName: inv.inviteeName,
                                );
                                Clipboard.setData(ClipboardData(text: msg));
                                LifeOsTopToast.show(
                                  context,
                                  'Đã sao chép tin nhắn mời để gửi lại.',
                                );
                              },
                              icon: const Icon(Icons.send_outlined, size: 15),
                              label: const Text('Gửi lại lời mời'),
                            ),
                            if (isManager)
                              TextButton.icon(
                                key: Key('revoke_invite_${inv.inviteCode}'),
                                style: TextButton.styleFrom(
                                  foregroundColor: c.error,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: state.isSubmitting
                                    ? null
                                    : () => context.read<FamilyBloc>().add(
                                        FamilyInviteRevokeRequested(
                                          actorUserId: currentUserId,
                                          familyId: family.id,
                                          inviteCode: inv.inviteCode,
                                        ),
                                      ),
                                icon: const Icon(
                                  Icons.cancel_outlined,
                                  size: 15,
                                ),
                                label: const Text('Thu hồi'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),

            // 3. Official Joined Members Section ("Thành viên chính thức")
            LifeOsSectionHeader(
              title: 'Thành viên chính thức (${family.members.length})',
              tone: LifeOsAccentTone.emerald,
            ),
            ...family.members.map((m) {
              final isSelf = m.userId == currentUserId;
              final net = balanceByUid[m.userId]?.netBalanceMinor ?? 0;
              final netLabel = net == 0
                  ? 'Đã cân bằng chi chung'
                  : (net > 0
                        ? 'Cần nhận lại +${VndAmount.format(net)}'
                        : 'Cần thanh toán -${VndAmount.format(net.abs())}');
              final netColor = net == 0
                  ? c.textSecondary
                  : (net > 0 ? c.success : c.warning);

              final canManageTarget =
                  !isSelf &&
                  m.role != HouseholdRole.owner &&
                  (isOwner || (isManager && m.role == HouseholdRole.member));

              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: LifeOsSoftCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: m.role == HouseholdRole.owner
                            ? c.primary
                            : c.primarySubtle,
                        child: Text(
                          m.fullName.trim().isEmpty
                              ? 'TV'
                              : m.fullName
                                    .trim()
                                    .characters
                                    .first
                                    .toUpperCase(),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: m.role == HouseholdRole.owner
                                ? Colors.white
                                : c.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSelf ? '${m.fullName} (Bạn)' : m.fullName,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              netLabel,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: netColor,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SemanticStatusBadge(
                        kind: m.role == HouseholdRole.owner
                            ? SemanticStatusKind.success
                            : SemanticStatusKind.info,
                        label: m.role.displayLabel,
                      ),
                      if (canManageTarget)
                        PopupMenuButton<String>(
                          key: Key('manage_member_menu_${m.userId}'),
                          enabled: !state.isSubmitting,
                          tooltip: 'Quản lý thành viên',
                          onSelected: (action) async {
                            if (action == 'promote_admin') {
                              context.read<FamilyBloc>().add(
                                FamilyMemberRoleUpdated(
                                  actorUserId: currentUserId,
                                  familyId: family.id,
                                  targetUserId: m.userId,
                                  targetName: m.fullName,
                                  newRole: HouseholdRole.admin,
                                ),
                              );
                            } else if (action == 'demote_member') {
                              context.read<FamilyBloc>().add(
                                FamilyMemberRoleUpdated(
                                  actorUserId: currentUserId,
                                  familyId: family.id,
                                  targetUserId: m.userId,
                                  targetName: m.fullName,
                                  newRole: HouseholdRole.member,
                                ),
                              );
                            } else if (action == 'remove_member') {
                              final ok = await showDestructiveConfirmDialog(
                                context: context,
                                title: 'Xóa ${m.fullName} khỏi nhóm?',
                                message:
                                    'Thành viên này sẽ không còn thấy chi tiêu chung, lịch hoặc công việc của "${family.name}".',
                                confirmLabel: 'Xóa khỏi nhóm',
                              );
                              if (ok && context.mounted) {
                                context.read<FamilyBloc>().add(
                                  FamilyMemberRemoved(
                                    actorUserId: currentUserId,
                                    familyId: family.id,
                                    targetUserId: m.userId,
                                    targetName: m.fullName,
                                  ),
                                );
                              }
                            }
                          },
                          itemBuilder: (_) => [
                            if (isOwner && m.role == HouseholdRole.member)
                              const PopupMenuItem(
                                value: 'promote_admin',
                                child: Text('Cấp quyền Quản trị'),
                              ),
                            if (isOwner && m.role == HouseholdRole.admin)
                              const PopupMenuItem(
                                value: 'demote_member',
                                child: Text('Chuyển về Thành viên'),
                              ),
                            PopupMenuItem(
                              value: 'remove_member',
                              child: Text(
                                'Xóa khỏi nhóm',
                                style: TextStyle(color: c.error),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SharedShoppingTabView extends StatefulWidget {
  final FamilyEntity family;
  final FamilyState state;
  final String currentUserId;
  final String currentUserName;

  const _SharedShoppingTabView({
    required this.family,
    required this.state,
    required this.currentUserId,
    required this.currentUserName,
  });

  @override
  State<_SharedShoppingTabView> createState() => _SharedShoppingTabViewState();
}

class _SharedShoppingTabViewState extends State<_SharedShoppingTabView> {
  String _statusFilter = 'all'; // 'all' | 'todo' | 'done'

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final allItems = widget.state.shoppingItems;
    final todoCount = allItems.where((i) => !i.isPurchased).length;
    final purchasedItems = allItems.where((i) => i.isPurchased).toList();
    final doneCount = purchasedItems.length;
    final purchasedTotalMinor = purchasedItems.fold<int>(
      0,
      (s, i) => s + i.estimatedPriceMinor,
    );
    final isSubmitting = widget.state.isSubmitting;
    final visibleItems = switch (_statusFilter) {
      'todo' => allItems.where((i) => !i.isPurchased).toList(),
      'done' => purchasedItems,
      _ => allItems,
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          key: const Key('shopping_list_view'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.dockClearance,
          ),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Danh sách Mua sắm Chung (${allItems.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                FilledButton.tonalIcon(
                  key: const Key('open_add_shopping_item_btn'),
                  onPressed: isSubmitting
                      ? null
                      : () => _showAddShoppingDialog(
                          context,
                          familyId: widget.family.id,
                          userName: widget.currentUserName,
                        ),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: const Text('Thêm món'),
                ),
              ],
            ),
            if (doneCount > 0) ...[
              const SizedBox(height: 10),
              LifeOsMintHeroCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const BananaGlassIcon(
                          assetPath: AppAssets.icCatShopping,
                          fallbackIcon: Icons.shopping_bag_rounded,
                          size: 36,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Đã mua $doneCount món · Tạm tính ${VndAmount.format(purchasedTotalMinor)}',
                                softWrap: true,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.8,
                                  color: c.textPrimary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              Text(
                                'Gộp các món đã mua để chia đều tiền nhóm nhanh.',
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
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const Key('checkout_purchased_to_split_btn'),
                          onPressed: isSubmitting
                              ? null
                              : () {
                                  final titlesSummary =
                                      purchasedItems.length <= 3
                                      ? purchasedItems
                                            .map((e) => e.title)
                                            .join(', ')
                                      : '${purchasedItems.take(2).map((e) => e.title).join(', ')} và ${purchasedItems.length - 2} món khác';
                                  final detailNote = purchasedItems
                                      .map(
                                        (e) =>
                                            '${e.title} (${e.quantityLabel}): ${VndAmount.format(e.estimatedPriceMinor)}',
                                      )
                                      .join(' · ');
                                  showSharedBillSplitSheet(
                                    context,
                                    family: widget.family,
                                    currentUserId: widget.currentUserId,
                                    currentUserName: widget.currentUserName,
                                    initialTitle: 'Đi chợ: $titlesSummary',
                                    initialAmountMinor: purchasedTotalMinor,
                                    initialTopic: SharedExpenseTopic.shopping,
                                    initialChoreNote: detailNote,
                                  );
                                },
                          icon: const Icon(Icons.call_split_rounded, size: 17),
                          label: const Text(
                            'Chốt các món đã mua → Chia tiền nhóm',
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const Key('clear_purchased_shopping_btn'),
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  final ok = await showDestructiveConfirmDialog(
                                    context: context,
                                    title: 'Dọn sạch $doneCount món đã mua?',
                                    message:
                                        'Các món đã đánh dấu đã mua sẽ bị xóa khỏi danh sách mua sắm chung.',
                                    confirmLabel: 'Dọn sạch',
                                  );
                                  if (ok && context.mounted) {
                                    context.read<FamilyBloc>().add(
                                      PurchasedShoppingItemsCleared(
                                        familyId: widget.family.id,
                                      ),
                                    );
                                  }
                                },
                          icon: Icon(
                            Icons.cleaning_services_outlined,
                            size: 16,
                            color: c.error,
                          ),
                          label: Text(
                            'Dọn món đã mua',
                            style: TextStyle(color: c.error),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (allItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('Tất cả (${allItems.length})'),
                      selected: _statusFilter == 'all',
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _statusFilter = 'all'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text('Cần mua ($todoCount)'),
                      selected: _statusFilter == 'todo',
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(
                        () => _statusFilter = _statusFilter == 'todo'
                            ? 'all'
                            : 'todo',
                      ),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text('Đã mua ($doneCount)'),
                      selected: _statusFilter == 'done',
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(
                        () => _statusFilter = _statusFilter == 'done'
                            ? 'all'
                            : 'done',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (allItems.isEmpty)
              LifeOsSoftCard(
                child: Column(
                  children: [
                    const BananaGlassIcon(
                      assetPath: AppAssets.icCatShopping,
                      fallbackIcon: Icons.shopping_cart_outlined,
                      size: 48,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Danh sách mua sắm chung đang trống',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cả nhà có thể cùng thêm đồ cần mua và chốt nhanh thành khoản chia tiền nhóm sau khi đi chợ.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: isSubmitting
                          ? null
                          : () => _showAddShoppingDialog(
                              context,
                              familyId: widget.family.id,
                              userName: widget.currentUserName,
                            ),
                      icon: const Icon(Icons.add_shopping_cart_rounded, size: 17),
                      label: const Text('Thêm món đầu tiên'),
                    ),
                  ],
                ),
              )
            else if (visibleItems.isEmpty)
              LifeOsSoftCard(
                child: Column(
                  children: [
                    const LifeOsIconSquircle(
                      icon: Icons.filter_list_off_rounded,
                      tone: LifeOsAccentTone.neutral,
                      size: 42,
                    ),
                    const SizedBox(height: 8),
                    const Text('Không có món đồ nào trong bộ lọc này.'),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => setState(() => _statusFilter = 'all'),
                      icon: const Icon(
                        Icons.filter_alt_off_rounded,
                        size: 16,
                      ),
                      label: const Text('Xem tất cả món đồ'),
                    ),
                  ],
                ),
              )
            else
              ...visibleItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LifeOsSoftCard(
                    onTap: () {
                      context.read<FamilyBloc>().add(
                        ShoppingItemToggled(
                          familyId: widget.family.id,
                          itemId: item.id,
                          isPurchased: !item.isPurchased,
                        ),
                      );
                    },
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: Checkbox(
                            value: item.isPurchased,
                            onChanged: (checked) {
                              context.read<FamilyBloc>().add(
                                ShoppingItemToggled(
                                  familyId: widget.family.id,
                                  itemId: item.id,
                                  isPurchased: checked ?? false,
                                ),
                              );
                            },
                          ),
                        ),
                        const BananaGlassIcon(
                          assetPath: AppAssets.icCatShopping,
                          fallbackIcon: Icons.shopping_bag_outlined,
                          size: 36,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.title} (${item.quantityLabel})',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: item.isPurchased
                                      ? c.textSecondary
                                      : c.textPrimary,
                                  decoration: item.isPurchased
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Dự kiến: ${VndAmount.format(item.estimatedPriceMinor)} · ${item.addedByName}',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: Key('delete_shopping_item_${item.id}'),
                          tooltip: 'Xóa món',
                          onPressed: isSubmitting
                              ? null
                              : () => context.read<FamilyBloc>().add(
                                  ShoppingItemDeleted(
                                    familyId: widget.family.id,
                                    itemId: item.id,
                                  ),
                                ),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: c.textSecondary,
                          ),
                        ),
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

  Future<void> _showAddShoppingDialog(
    BuildContext context, {
    required String familyId,
    required String userName,
  }) async {
    final bloc = context.read<FamilyBloc>();
    await showDialog<void>(
      context: context,
      builder: (_) => _AddShoppingItemDialog(
        bloc: bloc,
        familyId: familyId,
        userName: userName,
      ),
    );
  }
}

class _AddShoppingItemDialog extends StatefulWidget {
  const _AddShoppingItemDialog({
    required this.bloc,
    required this.familyId,
    required this.userName,
  });

  final FamilyBloc bloc;
  final String familyId;
  final String userName;

  @override
  State<_AddShoppingItemDialog> createState() => _AddShoppingItemDialogState();
}

class _AddShoppingItemDialogState extends State<_AddShoppingItemDialog> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final TextEditingController _priceCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm Món vào Danh sách Mua sắm'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tên hàng hóa'),
            const SizedBox(height: 6),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(hintText: 'VD: Gạo ST25'),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Số lượng'),
            const SizedBox(height: 6),
            TextField(controller: _qtyCtrl),
            const SizedBox(height: AppSpacing.sm),
            const Text('Giá dự kiến (VND)'),
            const SizedBox(height: 6),
            TextField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'VD: 50000'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        BlocProvider<FamilyBloc>.value(
          value: widget.bloc,
          child: BlocBuilder<FamilyBloc, FamilyState>(
            buildWhen: (p, c) => p.isSubmitting != c.isSubmitting,
            builder: (_, famState) => FilledButton(
              onPressed: famState.isSubmitting
                  ? null
                  : () {
                      final est = VndAmount.tryParseInput(_priceCtrl.text) ?? 0;
                      widget.bloc.add(
                        ShoppingItemAdded(
                          familyId: widget.familyId,
                          userName: widget.userName,
                          title: _titleCtrl.text,
                          quantityLabel: _qtyCtrl.text,
                          estimatedPriceMinor: est,
                        ),
                      );
                      Navigator.of(context).pop();
                    },
              child: const Text('Thêm'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Unified Household, Vehicles, Living & Health Hub housed cleanly inside Tab 4 (`Gia đình`),
/// keeping the bottom navigation bar strictly at 4 tabs + `+` while giving every
/// home/asset/wellness tool a clearly separated, logical home.
class _HouseholdAndAssetsHubView extends StatelessWidget {
  final bool showSoloGroupInviteCard;
  final VoidCallback? onCreateGroup;
  final VoidCallback? onJoinGroup;

  const _HouseholdAndAssetsHubView({
    required this.showSoloGroupInviteCard,
    this.onCreateGroup,
    this.onJoinGroup,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          key: const Key('family_household_assets_list_view'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.dockClearance,
          ),
          children: [
            if (showSoloGroupInviteCard) ...[
              const LifeOsSectionHeader(
                title: 'Không gian Nhóm & Chia tiền chung',
              ),
              LifeOsMintHeroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const LifeOsIconSquircle(
                          icon: Icons.family_restroom_rounded,
                          tone: LifeOsAccentTone.emerald,
                          solidFill: true,
                          size: 42,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Chưa tham gia nhóm nào',
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (onCreateGroup != null)
                          FilledButton.icon(
                            onPressed: onCreateGroup,
                            icon: const Icon(Icons.add_home_outlined, size: 17),
                            label: const Text('Tạo nhóm đầu tiên'),
                          ),
                        if (onJoinGroup != null)
                          OutlinedButton.icon(
                            onPressed: onJoinGroup,
                            icon: const Icon(
                              Icons.group_add_outlined,
                              size: 17,
                            ),
                            label: const Text('Nhập mã mời'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Group 1: Xe cộ, Điện nước, Tài liệu & Quỹ mục tiêu
            const LifeOsSectionHeader(
              title: 'Xe cộ, Nhà cửa & Giấy tờ',
              tone: LifeOsAccentTone.blue,
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('family_hub_vehicles_tile'),
                      icon: Icons.two_wheeler_rounded,
                      tone: LifeOsAccentTone.emerald,
                      title: 'Xe máy & Hóa đơn',
                      subtitle: 'Nhớt, nồi & chuẩn hãng',
                      onTap: () => context.push('/assets'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('family_hub_evn_tile'),
                      icon: Icons.electric_bolt_rounded,
                      tone: LifeOsAccentTone.amber,
                      title: 'Điện nước EVN',
                      subtitle: '5 bậc thang & nhà ở',
                      onTap: () => context.push('/home-living'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('family_hub_docs_tile'),
                      icon: Icons.folder_open_rounded,
                      tone: LifeOsAccentTone.purple,
                      title: 'Kho Tài liệu',
                      subtitle: 'Hợp đồng & giấy tờ',
                      onTap: () => context.push('/family-documents'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('family_hub_funds_tile'),
                      icon: Icons.savings_outlined,
                      tone: LifeOsAccentTone.emerald,
                      title: 'Quỹ mục tiêu',
                      subtitle: 'Tích lũy chung',
                      onTap: () => context.push('/family-funds'),
                    ),
                  ),
                ],
              ),
            ),

            // Group 2: Sức khỏe, Bếp, Hiếu Hỷ & Cài đặt
            const LifeOsSectionHeader(
              title: 'Sức khỏe, Bếp & Đời sống',
              tone: LifeOsAccentTone.coral,
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('family_hub_health_tile'),
                      icon: Icons.favorite_outline_rounded,
                      tone: LifeOsAccentTone.coral,
                      title: 'Sức khỏe & SOS',
                      subtitle: 'Tủ thuốc & BMI',
                      onTap: () => context.push('/health-hub'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('family_hub_kitchen_tile'),
                      icon: Icons.shopping_basket_outlined,
                      tone: LifeOsAccentTone.emerald,
                      title: 'Bếp & Đi chợ',
                      subtitle: 'Thực đơn & tủ lạnh',
                      onTap: () => context.push('/kitchen-groceries'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('family_hub_gift_tile'),
                      icon: Icons.card_giftcard_rounded,
                      tone: LifeOsAccentTone.purple,
                      title: 'Sổ Hiếu Hỷ',
                      subtitle: 'Mừng cưới & du lịch',
                      onTap: () => context.push('/social-ledger-travel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('family_hub_settings_tile'),
                      icon: Icons.settings_outlined,
                      tone: LifeOsAccentTone.neutral,
                      title: 'Cài đặt chung',
                      subtitle: 'Hồ sơ & giao diện',
                      onTap: () => context.push('/settings-hub'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
