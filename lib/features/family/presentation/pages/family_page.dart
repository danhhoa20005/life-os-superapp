import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
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
        if (state.selectedFamilyId != null &&
            state.selectedFamilyId != user.activeFamilyId) {
          context.read<AuthBloc>().add(
            AuthActiveFamilyChanged(state.selectedFamilyId!),
          );
        }
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
                    trailingAction: FilledButton.icon(
                      key: const Key('open_create_space_button'),
                      onPressed: () => _showCreateFamilyDialog(
                        context,
                        user.id,
                        user.fullName,
                      ),
                      icon: const Icon(Icons.add_home_outlined, size: 18),
                      label: const Text('Tạo nhóm'),
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
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(t.displayLabel),
                          ),
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
                    hintText:
                        'VD: Tổ ấm Minh & Lan / Căn hộ P.802 / Team Đà Lạt',
                  ),
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
    final bloc = context.read<FamilyBloc>()
      ..add(const FamilyInvitePreviewCleared());

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (sheetCtx) {
        return BlocProvider<FamilyBloc>.value(
          value: bloc,
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tham gia nhóm được mời',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    'Nhập mã FAM-XXXXXX hoặc dán nguyên tin nhắn mời',
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
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('join_family_invite_input'),
                          controller: ctrl,
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
                                if (raw.trim().isNotEmpty) {
                                  final extracted =
                                      FamilyInviteCodeExtractor.extractCode(
                                        raw,
                                      );
                                  ctrl.text = extracted;
                                  bloc.add(
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
                              bloc.add(FamilyInvitePreviewRequested(extracted));
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
                                : () => bloc.add(
                                    FamilyInvitePreviewRequested(ctrl.text),
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
                                onPressed: () => Navigator.of(sheetCtx).pop(),
                                child: const Text('Hủy'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                key: const Key('confirm_join_family_button'),
                                onPressed: () {
                                  bloc.add(
                                    FamilyJoinByCodeSubmitted(
                                      userId: userId,
                                      userName: userName,
                                      inviteCode: ctrl.text,
                                    ),
                                  );
                                  Navigator.of(sheetCtx).pop();
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
      },
    );
    ctrl.dispose();
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
                final taskCount = context.watch<TaskBloc>().state.tasks.length;
                final eventCount = context
                    .watch<CalendarBloc>()
                    .state
                    .events
                    .length;
                final totalFunds = context
                    .watch<BudgetBloc>()
                    .state
                    .funds
                    .fold<int>(0, (s, f) => s + f.balanceMinor);
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
                      const Divider(height: 22),
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: InkWell(
                                onTap: () => context.push('/tasks-board'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                          fontSize: 22,
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
                                        'việc cần làm',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            VerticalDivider(width: 12, color: c.separator),
                            Expanded(
                              flex: 3,
                              child: InkWell(
                                onTap: () => context.go('/planning'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                          fontSize: 22,
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
                                        'sự kiện',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            VerticalDivider(width: 12, color: c.separator),
                            Expanded(
                              flex: 4,
                              child: InkWell(
                                onTap: () => context.push('/family-funds'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                      child: Text(
                                        VndAmount.format(displayFund),
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
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Nhấn mở Quỹ chung >',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: c.primary,
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
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const Key('open_add_split_bill_button'),
                            onPressed: () =>
                                _showCreateSplitBillDialog(context),
                            icon: const Icon(
                              Icons.call_split_rounded,
                              size: 18,
                            ),
                            label: const Text('Chia khoản mới'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.push('/assets'),
                            icon: const Icon(
                              Icons.directions_car_outlined,
                              size: 17,
                            ),
                            label: const Text('Xe & Hóa đơn'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.push('/family-funds'),
                            icon: const Icon(Icons.savings_outlined, size: 17),
                            label: const Text('Quỹ chung'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.push('/family-documents'),
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
                );
              },
            ),

            const LifeOsSectionHeader(
              title: 'Cân đối chi tiêu thành viên',
              subtitle: 'Tự động tính bù trừ và tạo mã VietQR quyết toán',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  children: ledger.memberBalances.map((mb) {
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
                        vertical: 7,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            child: Text(
                              mb.fullName.isNotEmpty
                                  ? mb.fullName[0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
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
                                      mb.fullName,
                                      softWrap: true,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
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
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.md),
            Text(
              'Gợi ý thanh toán nhanh',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (ledger.suggestedTransfers.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text('Mọi khoản chi chung đã cân bằng.'),
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
                                  LifeOsTopToast.fromSnackBar(
                                    context,
                                    const SnackBar(
                                      content: Text(
                                        '✓ Đã sao chép mã chuyển khoản.',
                                      ),
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
                      leading: const CircleAvatar(
                        child: Icon(Icons.receipt_long_rounded),
                      ),
                      title: Text(
                        '${bill.title} · ${VndAmount.format(bill.totalAmountMinor)}',
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${bill.topic.displayLabel} · Trả trước bởi ${bill.paidByName} · ${bill.splitMethod.displayLabel}',
                          ),
                          if (bill.choreOrTaskNote != null &&
                              bill.choreOrTaskNote!.isNotEmpty)
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
              ...state.settlements
                  .take(10)
                  .map(
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
      for (final m in family.members)
        m.userId: TextEditingController(text: '1'),
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
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(t.displayLabel),
                            ),
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
                      hintText:
                          'VD: Lẩu cuối tuần / Mua nước lau sàn & giặt ủi',
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
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(m.fullName),
                            ),
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
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(m.displayLabel),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() {
                          method = v;
                          if (method == SplitMethod.percentage &&
                              selectedIds.isNotEmpty) {
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
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Hủy'),
              ),
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
  final nameCtrl = TextEditingController();
  final contactCtrl = TextEditingController();
  final bloc = context.read<FamilyBloc>();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (sheetCtx) {
      return BlocProvider<FamilyBloc>.value(
        value: bloc,
        child: BlocBuilder<FamilyBloc, FamilyState>(
          builder: (ctx, famState) {
            final c = TammySemanticColors.of(ctx);
            final viewInsets = MediaQuery.viewInsetsOf(ctx);
            final updatedFamily =
                famState.families.where((f) => f.id == family.id).firstOrNull ??
                family;
            final latestInvite = updatedFamily
                .activePendingInvites()
                .where((i) => i.inviteCode == famState.latestInviteCode)
                .firstOrNull;

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
                            icon: Icons.group_add_outlined,
                            tone: LifeOsAccentTone.emerald,
                            size: 40,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Mời thành viên vào "${family.name}"',
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Nhập tên để theo dõi người đang chờ hoặc để trống để tạo mã chung',
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
                      const SizedBox(height: 14),
                      TextField(
                        key: const Key('invite_member_name_input'),
                        controller: nameCtrl,
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
                        controller: contactCtrl,
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
                                bloc.add(
                                  FamilyInviteGenerated(
                                    userId: currentUserId,
                                    familyId: family.id,
                                    familyName: family.name,
                                    spaceType: family.spaceType,
                                    invitedByName: currentUserName,
                                    inviteeName: nameCtrl.text,
                                    inviteeContact: contactCtrl.text,
                                  ),
                                );
                              },
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('Tạo lời mời 7 ngày'),
                      ),
                      if (famState.latestInviteCode != null) ...[
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
                              SelectableText(
                                famState.latestInviteCode!,
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
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.tonalIcon(
                                    key: const Key('copy_invite_code_btn'),
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text: famState.latestInviteCode!,
                                        ),
                                      );
                                      LifeOsTopToast.show(
                                        ctx,
                                        'Đã sao chép mã mời ${famState.latestInviteCode!}.',
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
                                        inviteCode: famState.latestInviteCode!,
                                        inviteeName: latestInvite?.inviteeName,
                                      );
                                      Clipboard.setData(
                                        ClipboardData(text: msg),
                                      );
                                      LifeOsTopToast.show(
                                        ctx,
                                        'Đã sao chép lời mời đầy đủ để gửi Zalo / Tin nhắn.',
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
    },
  );
  nameCtrl.dispose();
  contactCtrl.dispose();
}

class _MembersAndGovernanceTabView extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                  const SizedBox(height: 6),
                  Text(
                    family.spaceType.subtitleHint,
                    softWrap: true,
                    style: Theme.of(context).textTheme.bodySmall,
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
                          onPressed: () => context.read<FamilyBloc>().add(
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
                ],
              ),
            ),

            // 2. Pending Invited Members Section ("Thành viên được mời · Đang chờ")
            LifeOsSectionHeader(
              title: 'Thành viên được mời (${activeInvites.length})',
              subtitle: activeInvites.isEmpty
                  ? 'Chưa có lời mời nào đang chờ phản hồi'
                  : 'Đang chờ nhập mã tham gia — tự động vào nhóm ngay khi xác nhận',
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
                        isManager
                            ? 'Nhấn "Mời thành viên" để tạo lời mời đích danh hoặc gửi mã tham gia qua Zalo / Tin nhắn.'
                            : 'Hiện không có lời mời mới nào đang chờ xác nhận.',
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
                                  if (inv.inviteeContact != null &&
                                      inv.inviteeContact!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      inv.inviteeContact!,
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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: c.primarySubtle,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                inv.inviteCode,
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
                                  'Đã sao chép mã mời ${inv.inviteCode}.',
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
                                onPressed: () => context.read<FamilyBloc>().add(
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
              subtitle: 'Cùng chia sẻ sổ chi chung, lịch nhóm & công việc',
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
  final String currentUserName;

  const _SharedShoppingTabView({
    required this.family,
    required this.state,
    required this.currentUserName,
  });

  @override
  State<_SharedShoppingTabView> createState() => _SharedShoppingTabViewState();
}

class _SharedShoppingTabViewState extends State<_SharedShoppingTabView> {
  String _statusFilter = 'all'; // 'all' | 'todo' | 'done'

  @override
  Widget build(BuildContext context) {
    final allItems = widget.state.shoppingItems;
    final todoCount = allItems.where((i) => !i.isPurchased).length;
    final doneCount = allItems.where((i) => i.isPurchased).length;
    final visibleItems = switch (_statusFilter) {
      'todo' => allItems.where((i) => !i.isPurchased).toList(),
      'done' => allItems.where((i) => i.isPurchased).toList(),
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
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showAddShoppingDialog(
                    context,
                    familyId: widget.family.id,
                    userName: widget.currentUserName,
                  ),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: const Text('Thêm món'),
                ),
              ],
            ),
            if (allItems.isNotEmpty) ...[
              const SizedBox(height: 8),
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
                        () => _statusFilter =
                            _statusFilter == 'todo' ? 'all' : 'todo',
                      ),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text('Đã mua ($doneCount)'),
                      selected: _statusFilter == 'done',
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(
                        () => _statusFilter =
                            _statusFilter == 'done' ? 'all' : 'done',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (allItems.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text('Danh sách mua sắm chung đang trống.'),
                ),
              )
            else if (visibleItems.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      const Text('Không có món đồ nào trong bộ lọc này.'),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => setState(() => _statusFilter = 'all'),
                        icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                        label: const Text('Xem tất cả món đồ'),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...visibleItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Card(
                    child: CheckboxListTile(
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
                      title: Text(
                        '${item.title} (${item.quantityLabel})',
                        style: TextStyle(
                          decoration: item.isPurchased
                              ? TextDecoration.lineThrough
                              : null,
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
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
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
                subtitle: 'Gia đình, nhà ở ghép hoặc nhóm bạn đi du lịch',
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chưa tham gia nhóm nào',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tạo không gian chung để chia hóa đơn, giao việc và đi chợ cùng nhau.',
                                style: TextStyle(
                                  fontSize: 12.2,
                                  height: 1.3,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
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
              subtitle:
                  'Phương tiện, hóa đơn định kỳ, điện nước EVN và hợp đồng',
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
              subtitle:
                  'Tủ thuốc gia đình, thực đơn đi chợ, hiếu hỷ & hệ thống',
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
