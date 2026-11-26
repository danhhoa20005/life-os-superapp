import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/services/native_home_widget_bridge.dart';
import '../../../../core/utils/omni_action_executor.dart';
import '../../../../core/utils/smart_omni_intent_parser.dart';
import '../../../../core/utils/smart_quick_entry_parser.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/voice_smart_capture_sheet.dart';
import '../../../authentication/domain/entities/user_entity.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../../transactions/presentation/bloc/transaction_state.dart';
import '../bloc/dashboard_bloc.dart';

/// Google Material You (Material 3) Interactive Home-Screen AppWidget Studio & Auto-Sync Hub.
class HomeWidgetsStudioPage extends StatefulWidget {
  const HomeWidgetsStudioPage({super.key});

  @override
  State<HomeWidgetsStudioPage> createState() => _HomeWidgetsStudioPageState();
}

class _HomeWidgetsStudioPageState extends State<HomeWidgetsStudioPage> {
  static const Uuid _uuid = Uuid();

  String _voiceStatusHint = 'Chạm nói, gõ nhanh hoặc bấm mức bên dưới';
  String? _lastUndoTxId;
  String? _lastUndoLabel;

  bool _hideBalances = false;
  int _wealthViewMode =
      0; // 0 = Net Worth, 1 = Monthly Surplus, 2 = Today Spend

  int _groupMembers = 3;
  String _groupLiveStatus = 'Chọn số người rồi chạm mức chia nhanh bên dưới';

  int _safeWidgetMode = 0; // 0 = Safe Spend, 1 = Hydration

  @override
  void initState() {
    super.initState();
    UserBehaviorPrefs.loadHideBalances().then((masked) {
      if (mounted) {
        setState(() => _hideBalances = masked);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final fam = context.read<FamilyBloc>().state.activeFamily;
      if (fam != null && fam.members.length >= 2) {
        setState(() => _groupMembers = fam.members.length.clamp(2, 20));
      }
    });
  }

  String _formatVndOrMasked(int minor, {String signPrefix = ''}) {
    if (_hideBalances) {
      return '$signPrefix•••••••• ₫';
    }
    if (signPrefix.isNotEmpty) {
      return '$signPrefix${VndAmount.format(minor.abs())}';
    }
    return VndAmount.format(minor);
  }

  String _resolveWalletId(BuildContext context) {
    final wallets = context.read<TransactionListBloc>().state.wallets;
    return UserBehaviorPrefs.resolvePreferredWalletId(wallets.map((w) => w.id));
  }

  Future<void> _pinWidget(
    BuildContext context,
    String kind,
    String title,
  ) async {
    final ok = await sl<NativeHomeWidgetBridge>().requestPinWidget(kind);
    if (!context.mounted) return;
    LifeOsTopToast.show(
      context,
      ok
          ? 'Đã mở hộp thoại hệ thống Android để ghim "$title" ra màn hình chính!'
          : 'Nhấn giữ ngoài Màn hình chính điện thoại -> Tiện ích (Widgets) -> LifeOS để đặt "$title".',
      kind: ok ? LifeOsToastKind.success : LifeOsToastKind.info,
    );
  }

  Future<void> _forceSyncAllWidgets(
    BuildContext context, {
    required bool autoConfirm,
    required String groupTitle,
    required String runwayLabel,
    required int usedPct,
  }) async {
    final dash = context.read<DashboardBloc>().state.data;
    await sl<NativeHomeWidgetBridge>().syncWidgets(
      netWorth: VndAmount.format(dash.netWorthMinor),
      monthlyIncome: '+${VndAmount.format(dash.monthlyIncomeMinor)}',
      monthlyExpense: '-${VndAmount.format(dash.monthlyExpenseMinor)}',
      todayExpense: VndAmount.format(dash.todayExpenseMinor),
      safeDaily: VndAmount.format(dash.dailySafeToSpendMinor),
      wealthBadge: autoConfirm ? 'Auto-Ledger' : 'Đổi góc nhìn',
      groupTitle: groupTitle,
      groupStatus: _groupLiveStatus,
      runwayLabel: runwayLabel,
      dailyUsedPct: usedPct,
      netWorthMinor: dash.netWorthMinor,
      monthlyIncomeMinor: dash.monthlyIncomeMinor,
      monthlyExpenseMinor: dash.monthlyExpenseMinor,
      todayExpenseMinor: dash.todayExpenseMinor,
      safeDailyMinor: dash.dailySafeToSpendMinor,
      groupMemberCount: _groupMembers,
      hideBalances: _hideBalances,
    );
    if (!context.mounted) return;
    LifeOsTopToast.show(
      context,
      'Đã đồng bộ số liệu & trạng thái tương tác ra cả 4 Widget màn hình chính!',
    );
  }

  Future<void> _recordQuickWidgetExpense(
    UserEntity user, {
    required String label,
    required String categoryId,
    required String categoryName,
    required int amountMinor,
    TransactionKind kind = TransactionKind.expense,
  }) async {
    final opId = _uuid.v4();
    final walletId = _resolveWalletId(context);
    final outcome = await context
        .read<TransactionActionBloc>()
        .submitAndAwaitCreate(
          TransactionCreateSubmitted(
            operationId: opId,
            userId: user.id,
            walletId: walletId,
            categoryId: categoryId,
            categoryName: categoryName,
            kind: kind,
            amountMinor: amountMinor,
            merchant: label,
            note: 'Ghi nhanh ngay trên Widget',
            occurredAt: DateTime.now(),
          ),
        );
    if (!mounted) return;
    final createdTx = outcome.lastCreatedTransaction;
    if (outcome.status != ActionStatus.success || createdTx == null) {
      LifeOsTopToast.show(
        context,
        outcome.failure?.message ??
            'Không thể lưu giao dịch từ Widget — vui lòng thử lại.',
        kind: LifeOsToastKind.error,
      );
      return;
    }
    setState(() {
      _lastUndoTxId = createdTx.id;
      _lastUndoLabel = label;
      _voiceStatusHint = 'Đã ghi: $label (${VndAmount.format(amountMinor)})';
    });
    LifeOsTopToast.show(
      context,
      'Widget đã ghi tại chỗ: $label (${VndAmount.format(amountMinor)})',
    );
  }

  void _undoLastWidgetExpense(UserEntity user) {
    final txId = _lastUndoTxId;
    final label = _lastUndoLabel ?? 'Giao dịch';
    if (txId == null) {
      setState(() {
        _voiceStatusHint = 'Chưa có thao tác mới nào để hoàn tác';
      });
      LifeOsTopToast.show(
        context,
        'Chưa có thao tác Widget mới nào cần hoàn tác.',
        kind: LifeOsToastKind.info,
      );
      return;
    }
    context.read<TransactionActionBloc>().add(
      TransactionReverseRequested(
        userId: user.id,
        transactionId: txId,
        reason: 'Hoàn tác ngay trên Widget',
      ),
    );
    setState(() {
      _lastUndoTxId = null;
      _lastUndoLabel = null;
      _voiceStatusHint = 'Đã hoàn tác: $label';
    });
    LifeOsTopToast.show(
      context,
      'Đã hoàn tác khoản "$label" ngay tại chỗ.',
      kind: LifeOsToastKind.info,
    );
  }

  Future<void> _recordQuickGroupSplit(
    UserEntity user, {
    required String label,
    required int amountMinor,
  }) async {
    final members = _groupMembers.clamp(2, 20);
    final perPerson = amountMinor ~/ members;
    final status =
        'Đã chia $label: ${VndAmount.format(perPerson)}/người ($members người)';
    setState(() {
      _groupLiveStatus = status;
      _voiceStatusHint = status;
    });
    await OmniActionExecutor.executeDraft(
      toastContext: context,
      draft: OmniActionDraft(
        id: _uuid.v4(),
        kind: OmniActionKind.groupSplit,
        title: label,
        amountMinor: amountMinor,
        participantCount: members,
        originLabel: 'Widget màn hình chính',
      ),
      user: user,
      walletId: _resolveWalletId(context),
      familyBloc: context.read<FamilyBloc>(),
      showSuccessToast: false,
    );
    if (!mounted) return;
    LifeOsTopToast.show(context, status);
  }

  void _recordQuickWater(UserEntity user, int deltaMl) {
    final hyd = context.read<DailyLifeBloc>().state.snapshot.hydration;
    context.read<DailyLifeBloc>().add(
      WaterIntakeLogged(
        userId: user.id,
        deltaMl: deltaMl,
        targetWaterMl: hyd.targetWaterMl,
      ),
    );
    setState(() {
      _safeWidgetMode = 1;
      _voiceStatusHint = 'Đã ghi uống +$deltaMl ml nước trên Widget';
    });
    LifeOsTopToast.show(
      context,
      'Đã cộng +$deltaMl ml nước ngay trên Widget!',
      kind: LifeOsToastKind.info,
    );
  }

  Future<void> _toggleMask() async {
    final next = !_hideBalances;
    setState(() => _hideBalances = next);
    await UserBehaviorPrefs.saveHideBalances(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = context.select((AuthBloc b) => b.state.user);
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dash = context.select((DashboardBloc b) => b.state.data);
    final family = context.select((FamilyBloc b) => b.state.activeFamily);
    final hydration = context.select(
      (DailyLifeBloc b) => b.state.snapshot.hydration,
    );
    final runway = EmergencyRunwaySnapshot.compute(
      netLiquidMinor: dash.netWorthMinor,
      monthlyExpenseMinor: dash.monthlyExpenseMinor,
    );
    final usedPct = dash.dailySafeToSpendMinor > 0
        ? ((dash.todayExpenseMinor * 100) ~/ dash.dailySafeToSpendMinor).clamp(
            4,
            100,
          )
        : 15;
    final groupTitle = family != null
        ? '${family.name} · $_groupMembers người'
        : 'Tổ ấm & Hội nhóm';
    final runwayLabel =
        'Quỹ dự phòng: ${runway.monthsOfRunway.toStringAsFixed(1)} tháng · ${runway.statusBadge}';

    final (wealthModeTitle, wealthHeadline) = switch (_wealthViewMode) {
      1 => (
        'Dư ròng tháng này',
        _formatVndOrMasked(
          dash.monthlyIncomeMinor - dash.monthlyExpenseMinor,
          signPrefix: (dash.monthlyIncomeMinor - dash.monthlyExpenseMinor) > 0
              ? '+'
              : '',
        ),
      ),
      2 => ('Đã chi tiêu hôm nay', _formatVndOrMasked(dash.todayExpenseMinor)),
      _ => ('Tổng tài sản ròng', _formatVndOrMasked(dash.netWorthMinor)),
    };

    final waterTarget = hydration.targetWaterMl.clamp(500, 10000);
    final waterPct = ((hydration.waterMl * 100) ~/ waterTarget).clamp(4, 100);
    final waterRemain = (waterTarget - hydration.waterMl).clamp(0, 10000);

    // Exact Google Material 3 Widget Surface Tokens
    final m3WidgetSurface = isDark ? const Color(0xFF191C1A) : Colors.white;
    final m3TonalBox = isDark
        ? const Color(0xFF232A26)
        : const Color(0xFFF1F8F3);
    final m3IncomeBox = isDark
        ? const Color(0xFF132B1D)
        : const Color(0xFFEAFBF0);
    final m3ExpenseBox = isDark
        ? const Color(0xFF31181B)
        : const Color(0xFFFEF2F2);
    final m3TonalPillBg = isDark
        ? const Color(0xFF183925)
        : const Color(0xFFDCFCE7);
    final m3TonalPillFg = isDark
        ? const Color(0xFF86EFAC)
        : const Color(0xFF0F5132);
    final m3Stroke = isDark ? const Color(0xFF2C3731) : const Color(0xFFE4E7EC);

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              LifeOsTopBrandHeader(
                title: '4 Widget Chuẩn Google M3',
                showBackButton: true,
                trailingAction: IconButton.filled(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Ghi bằng giọng nói',
                  onPressed: () => showVoiceSmartCaptureSheet(context),
                  icon: const Icon(Icons.mic_rounded, size: 18),
                ),
              ),
              Expanded(
                child: BlocBuilder<NotificationIngestionBloc, NotificationIngestionState>(
                  builder: (context, notifState) {
                    final consent = notifState.consent;
                    final notifEnabled = consent?.enabled ?? false;
                    final autoConfirm = consent?.autoConfirmSignals ?? false;
                    final allowedPkgs =
                        consent?.allowedPackages ??
                        kSupportedVnBanks.map((b) => b.packageName).toList();

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppSpacing.maxContentWidth,
                        ),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            2,
                            AppSpacing.md,
                            AppSpacing.xl,
                          ),
                          children: [
                            // 1. Auto-Sync & Direct On-Home-Screen Mode Banner
                            LifeOsMintHeroCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.touch_app_rounded,
                                        tone: LifeOsAccentTone.emerald,
                                        solidFill: true,
                                        size: 38,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Tương Tác Trực Tiếp Ngoài Màn Hình Chính',
                                              style: TextStyle(
                                                fontSize: 14.2,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              'Bấm nút trên Widget để ghi chi tiêu, chia tiền, uống nước hoặc ẩn số dư ngay tại màn Home mà không mở vào trong app',
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
                                  const SizedBox(height: 8),
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: Text(
                                      'Nhận diện biến động số dư Ngân hàng',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    subtitle: Text(
                                      notifState.isNativePermissionGranted
                                          ? 'Đã cấp quyền đọc thông báo'
                                          : 'Nhấn để cấp quyền đọc thông báo ngân hàng',
                                      style: TextStyle(
                                        fontSize: 11.2,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                    value: notifEnabled,
                                    onChanged: (next) {
                                      context
                                          .read<NotificationIngestionBloc>()
                                          .add(
                                            ConsentConfigUpdated(
                                              userId: user.id,
                                              enabled: next,
                                              allowedPackages:
                                                  allowedPkgs.isEmpty
                                                  ? kSupportedVnBanks
                                                        .map(
                                                          (b) => b.packageName,
                                                        )
                                                        .toList()
                                                  : allowedPkgs,
                                              autoConfirmSignals: autoConfirm,
                                            ),
                                          );
                                      if (next &&
                                          !notifState
                                              .isNativePermissionGranted) {
                                        context
                                            .read<NotificationIngestionBloc>()
                                            .add(
                                              const OpenNativePermissionSettingsRequested(),
                                            );
                                      }
                                    },
                                  ),
                                  SwitchListTile.adaptive(
                                    key: const Key(
                                      'zero_touch_auto_confirm_switch',
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: Text(
                                      'Tự động ghi thu chi & cập nhật Widget',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    value: autoConfirm,
                                    onChanged: (next) {
                                      context
                                          .read<NotificationIngestionBloc>()
                                          .add(
                                            ConsentConfigUpdated(
                                              userId: user.id,
                                              enabled: next
                                                  ? true
                                                  : notifEnabled,
                                              allowedPackages:
                                                  allowedPkgs.isEmpty
                                                  ? kSupportedVnBanks
                                                        .map(
                                                          (b) => b.packageName,
                                                        )
                                                        .toList()
                                                  : allowedPkgs,
                                              autoConfirmSignals: next,
                                            ),
                                          );
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                          key: const Key(
                                            'sync_widgets_now_button',
                                          ),
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 10,
                                            ),
                                          ),
                                          onPressed: () => _forceSyncAllWidgets(
                                            context,
                                            autoConfirm: autoConfirm,
                                            groupTitle: groupTitle,
                                            runwayLabel: runwayLabel,
                                            usedPct: usedPct,
                                          ),
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                            size: 16,
                                          ),
                                          label: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text('Đồng bộ Widget'),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 10,
                                            ),
                                          ),
                                          onPressed: () => context.push(
                                            '/notifications-privacy',
                                          ),
                                          icon: const Icon(
                                            Icons.cloud_sync_outlined,
                                            size: 16,
                                          ),
                                          label: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text('Cổng QR & Ngân hàng'),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 2. WIDGET 01: Interactive Voice & 1-Tap Expense Quick Bar (4x2)
                            _GoogleM3WidgetShowcaseCard(
                              badgeLabel:
                                  'WIDGET 01 · 4×2 · THANH TÌM KIẾM & GIỌNG NÓI PIXEL',
                              description:
                                  'Bấm chip +35k/+50k/+80k để ghi ngay trên màn Home hoặc bật khung nói nổi trên hình nền.',
                              surfaceColor: m3WidgetSurface,
                              strokeColor: m3Stroke,
                              onPin: () => _pinWidget(
                                context,
                                'voice',
                                'Thanh Giọng nói & Ghi nhanh',
                              ),
                              widgetPreview: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsLeafMark(
                                        size: 26,
                                        borderRadius: 8,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Material(
                                          color: m3TonalBox,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            onTap: () =>
                                                showVoiceSmartCaptureSheet(
                                                  context,
                                                  autoStartListening: false,
                                                ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 11,
                                                    vertical: 6,
                                                  ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _voiceStatusHint,
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: c.textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 1),
                                                  Text(
                                                    'Chi hôm nay: ${_formatVndOrMasked(dash.todayExpenseMinor)}',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      color: c.textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Material(
                                        color: c.primary,
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: () =>
                                              showVoiceSmartCaptureSheet(
                                                context,
                                                autoStartListening: true,
                                              ),
                                          child: const SizedBox(
                                            width: 38,
                                            height: 38,
                                            child: Icon(
                                              Icons.mic_rounded,
                                              color: Colors.white,
                                              size: 19,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Material(
                                        color: m3TonalPillBg,
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: () => showVoiceSmartCaptureSheet(
                                            context,
                                            initialTranscript:
                                                'Ăn lẩu bò 450 nghìn chia đều $_groupMembers người',
                                          ),
                                          child: SizedBox(
                                            width: 38,
                                            height: 38,
                                            child: Icon(
                                              Icons.groups_rounded,
                                              color: m3TonalPillFg,
                                              size: 19,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_voice_chip_35k',
                                        ),
                                        label: '+Cà phê 35k',
                                        bgColor: m3TonalPillBg,
                                        fgColor: m3TonalPillFg,
                                        onTap: () => _recordQuickWidgetExpense(
                                          user,
                                          label: 'Cà phê',
                                          categoryId: 'cat_food',
                                          categoryName: 'Ăn uống',
                                          amountMinor: 35000,
                                        ),
                                      ),
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_voice_chip_50k',
                                        ),
                                        label: '+Ăn 50k',
                                        bgColor: m3TonalPillBg,
                                        fgColor: m3TonalPillFg,
                                        onTap: () => _recordQuickWidgetExpense(
                                          user,
                                          label: 'Ăn uống',
                                          categoryId: 'cat_food',
                                          categoryName: 'Ăn uống',
                                          amountMinor: 50000,
                                        ),
                                      ),
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_voice_chip_80k',
                                        ),
                                        label: '+Xăng 80k',
                                        bgColor: m3TonalPillBg,
                                        fgColor: m3TonalPillFg,
                                        onTap: () => _recordQuickWidgetExpense(
                                          user,
                                          label: 'Đổ xăng',
                                          categoryId: 'cat_transport',
                                          categoryName: 'Di chuyển',
                                          amountMinor: 80000,
                                        ),
                                      ),
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_voice_undo_btn',
                                        ),
                                        label: 'Hoàn tác',
                                        bgColor: m3TonalBox,
                                        fgColor: c.textSecondary,
                                        onTap: () =>
                                            _undoLastWidgetExpense(user),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // 3. WIDGET 02: Interactive Net Worth & Cashflow Card (4x2)
                            _GoogleM3WidgetShowcaseCard(
                              badgeLabel: 'WIDGET 02 · 4×2 · TÀI SẢN & THU CHI',
                              description:
                                  'Chạm "Ẩn số" để che số dư riêng tư hoặc "Đổi góc nhìn" ngay ngoài màn hình chính.',
                              surfaceColor: m3WidgetSurface,
                              strokeColor: m3Stroke,
                              onPin: () => _pinWidget(
                                context,
                                'wealth',
                                'Tài sản & Dòng tiền',
                              ),
                              widgetPreview: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsLeafMark(
                                        size: 20,
                                        borderRadius: 6,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          wealthModeTitle,
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 11.8,
                                            fontWeight: FontWeight.w600,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ),
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_wealth_mask_btn',
                                        ),
                                        label: _hideBalances
                                            ? 'Hiện số'
                                            : 'Ẩn số',
                                        bgColor: m3TonalBox,
                                        fgColor: c.textSecondary,
                                        onTap: _toggleMask,
                                      ),
                                      const SizedBox(width: 5),
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_wealth_mode_btn',
                                        ),
                                        label: switch (_wealthViewMode) {
                                          1 => 'Góc 2/3',
                                          2 => 'Góc 3/3',
                                          _ => 'Đổi góc nhìn',
                                        },
                                        bgColor: m3TonalPillBg,
                                        fgColor: m3TonalPillFg,
                                        onTap: () => setState(() {
                                          _wealthViewMode =
                                              (_wealthViewMode + 1) % 3;
                                        }),
                                      ),
                                      const SizedBox(width: 5),
                                      Material(
                                        color: c.primary,
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          key: const Key(
                                            'studio_wealth_quick_add_btn',
                                          ),
                                          customBorder: const CircleBorder(),
                                          onTap: () =>
                                              showVoiceSmartCaptureSheet(
                                                context,
                                                autoStartListening: false,
                                              ),
                                          child: const SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: Icon(
                                              Icons.add_rounded,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => setState(() {
                                      _wealthViewMode =
                                          (_wealthViewMode + 1) % 3;
                                    }),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        wealthHeadline,
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: c.textPrimary,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Material(
                                          color: m3IncomeBox,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            onTap: () =>
                                                showVoiceSmartCaptureSheet(
                                                  context,
                                                  autoStartListening: false,
                                                  initialTranscript:
                                                      'Nhận thưởng 1tr5',
                                                ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 7,
                                                  ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Thu tháng (+Ghi)',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: c.textSecondary,
                                                    ),
                                                  ),
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Text(
                                                      _formatVndOrMasked(
                                                        dash.monthlyIncomeMinor,
                                                        signPrefix: '+',
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w800,
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
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Material(
                                          color: m3ExpenseBox,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            onTap: () =>
                                                showVoiceSmartCaptureSheet(
                                                  context,
                                                  autoStartListening: false,
                                                ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 7,
                                                  ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Chi tháng (+Ghi)',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: c.textSecondary,
                                                    ),
                                                  ),
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Text(
                                                      _formatVndOrMasked(
                                                        dash.monthlyExpenseMinor,
                                                        signPrefix: '-',
                                                      ),
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: Color(
                                                          0xFFDC2626,
                                                        ),
                                                        fontFeatures: [
                                                          FontFeature.tabularFigures(),
                                                        ],
                                                      ),
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
                                ],
                              ),
                            ),

                            // 4. WIDGET 03: Interactive Family & Roommate Split Hub (4x2)
                            _GoogleM3WidgetShowcaseCard(
                              badgeLabel:
                                  'WIDGET 03 · 4×2 · CHIA TIỀN NHÓM & GIA ĐÌNH',
                              description:
                                  'Tăng/giảm số người (- / +) và bấm chia nhanh +150k / +300k ngay trên màn hình chính.',
                              surfaceColor: m3WidgetSurface,
                              strokeColor: m3Stroke,
                              onPin: () => _pinWidget(
                                context,
                                'group',
                                'Chia Tiền Nhóm & Gia Đình',
                              ),
                              widgetPreview: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsLeafMark(
                                        size: 20,
                                        borderRadius: 6,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          groupTitle,
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 11.8,
                                            fontWeight: FontWeight.w600,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ),
                                      _WidgetStepperButton(
                                        buttonKey: const Key(
                                          'studio_group_minus_btn',
                                        ),
                                        symbol: '-',
                                        bgColor: m3TonalBox,
                                        fgColor: c.textPrimary,
                                        onTap: () => setState(() {
                                          _groupMembers = (_groupMembers - 1)
                                              .clamp(2, 20);
                                          _groupLiveStatus =
                                              'Chế độ chia đều $_groupMembers người · Chạm mức bên dưới';
                                        }),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        child: Text(
                                          '$_groupMembers người',
                                          style: TextStyle(
                                            fontSize: 11.2,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                      ),
                                      _WidgetStepperButton(
                                        buttonKey: const Key(
                                          'studio_group_plus_btn',
                                        ),
                                        symbol: '+',
                                        bgColor: m3TonalPillBg,
                                        fgColor: m3TonalPillFg,
                                        onTap: () => setState(() {
                                          _groupMembers = (_groupMembers + 1)
                                              .clamp(2, 20);
                                          _groupLiveStatus =
                                              'Chế độ chia đều $_groupMembers người · Chạm mức bên dưới';
                                        }),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _groupLiveStatus,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 12.8,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_group_split_150k_btn',
                                        ),
                                        label: '+Ăn 150k',
                                        bgColor: m3TonalPillBg,
                                        fgColor: m3TonalPillFg,
                                        onTap: () => _recordQuickGroupSplit(
                                          user,
                                          label: 'Ăn chung',
                                          amountMinor: 150000,
                                        ),
                                      ),
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_group_split_300k_btn',
                                        ),
                                        label: '+Hóa đơn 300k',
                                        bgColor: m3TonalPillBg,
                                        fgColor: m3TonalPillFg,
                                        onTap: () => _recordQuickGroupSplit(
                                          user,
                                          label: 'Hóa đơn chung',
                                          amountMinor: 300000,
                                        ),
                                      ),
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_group_voice_btn',
                                        ),
                                        label: 'Nói chia',
                                        icon: Icons.mic_rounded,
                                        bgColor: c.primary,
                                        fgColor: Colors.white,
                                        onTap: () => showVoiceSmartCaptureSheet(
                                          context,
                                          initialTranscript:
                                              'Tiền điện nước 900k chia đều $_groupMembers người',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // 5. WIDGET 04: Interactive Daily Safe Spend & Hydration +250ml (3x2)
                            _GoogleM3WidgetShowcaseCard(
                              badgeLabel:
                                  'WIDGET 04 · 3×2 · HẠN MỨC & NƯỚC UỐNG HÔM NAY',
                              description:
                                  'Ghi chi tiêu -20k/-50k hoặc đổi sang chế độ Uống nước +250ml ngay ngoài màn hình chính.',
                              surfaceColor: m3WidgetSurface,
                              strokeColor: m3Stroke,
                              onPin: () => _pinWidget(
                                context,
                                'safe_spend',
                                'Hạn Mức An Toàn Hôm Nay',
                              ),
                              widgetPreview: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _safeWidgetMode == 1
                                            ? Icons.water_drop_rounded
                                            : Icons.verified_user_rounded,
                                        size: 18,
                                        color: c.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _safeWidgetMode == 1
                                              ? 'Nước uống hôm nay'
                                              : 'Hạn mức hôm nay',
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ),
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_safe_badge_toggle_btn',
                                        ),
                                        label: _safeWidgetMode == 1
                                            ? '$waterPct% · Đổi'
                                            : 'Đã dùng $usedPct%',
                                        bgColor: m3TonalPillBg,
                                        fgColor: m3TonalPillFg,
                                        onTap: () => setState(() {
                                          _safeWidgetMode = _safeWidgetMode == 0
                                              ? 1
                                              : 0;
                                        }),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _safeWidgetMode == 1
                                          ? '${hydration.waterMl} / $waterTarget ml'
                                          : _formatVndOrMasked(
                                              dash.dailySafeToSpendMinor,
                                            ),
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                        color: c.textPrimary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      minHeight: 9,
                                      value:
                                          ((_safeWidgetMode == 1
                                                      ? waterPct
                                                      : usedPct) /
                                                  100)
                                              .clamp(0.06, 1.0),
                                      color: c.primary,
                                      backgroundColor: isDark
                                          ? const Color(0xFF2D3748)
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _safeWidgetMode == 1
                                        ? (waterRemain == 0
                                              ? 'Đã hoàn thành mục tiêu nước hôm nay!'
                                              : 'Còn $waterRemain ml để đủ chuẩn $waterTarget ml')
                                        : runwayLabel,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 11.2,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_safe_action_1_btn',
                                        ),
                                        label: _safeWidgetMode == 1
                                            ? '+250ml'
                                            : '-20k Nhanh',
                                        bgColor: m3TonalPillBg,
                                        fgColor: m3TonalPillFg,
                                        onTap: () {
                                          if (_safeWidgetMode == 1) {
                                            _recordQuickWater(user, 250);
                                          } else {
                                            _recordQuickWidgetExpense(
                                              user,
                                              label: 'Chi vặt',
                                              categoryId: 'cat_other_exp',
                                              categoryName: 'Chi tiêu khác',
                                              amountMinor: 20000,
                                            );
                                          }
                                        },
                                      ),
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_safe_action_2_btn',
                                        ),
                                        label: _safeWidgetMode == 1
                                            ? '+350ml'
                                            : '-50k Ăn uống',
                                        bgColor: c.primary,
                                        fgColor: Colors.white,
                                        onTap: () {
                                          if (_safeWidgetMode == 1) {
                                            _recordQuickWater(user, 350);
                                          } else {
                                            _recordQuickWidgetExpense(
                                              user,
                                              label: 'Ăn uống',
                                              categoryId: 'cat_food',
                                              categoryName: 'Ăn uống',
                                              amountMinor: 50000,
                                            );
                                          }
                                        },
                                      ),
                                      _WidgetActionPill(
                                        pillKey: const Key(
                                          'studio_safe_mode_toggle_btn',
                                        ),
                                        label: _safeWidgetMode == 1
                                            ? 'Hạn mức'
                                            : 'Nước',
                                        bgColor: m3TonalBox,
                                        fgColor: c.textSecondary,
                                        onTap: () => setState(() {
                                          _safeWidgetMode = _safeWidgetMode == 0
                                              ? 1
                                              : 0;
                                        }),
                                      ),
                                    ],
                                  ),
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
    );
  }
}

class _WidgetActionPill extends StatelessWidget {
  final Key? pillKey;
  final String label;
  final IconData? icon;
  final Color bgColor;
  final Color fgColor;
  final VoidCallback onTap;

  const _WidgetActionPill({
    this.pillKey,
    required this.label,
    this.icon,
    required this.bgColor,
    required this.fgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: pillKey,
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fgColor),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WidgetStepperButton extends StatelessWidget {
  final Key? buttonKey;
  final String symbol;
  final Color bgColor;
  final Color fgColor;
  final VoidCallback onTap;

  const _WidgetStepperButton({
    this.buttonKey,
    required this.symbol,
    required this.bgColor,
    required this.fgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Center(
            child: Text(
              symbol,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: fgColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleM3WidgetShowcaseCard extends StatelessWidget {
  final String badgeLabel;
  final String description;
  final Color surfaceColor;
  final Color strokeColor;
  final Widget widgetPreview;
  final VoidCallback onPin;

  const _GoogleM3WidgetShowcaseCard({
    required this.badgeLabel,
    required this.description,
    required this.surfaceColor,
    required this.strokeColor,
    required this.widgetPreview,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LifeOsSoftCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    badgeLabel,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: c.primary,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: onPin,
                  icon: const Icon(Icons.widgets_outlined, size: 15),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Ghim Widget'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              description,
              style: TextStyle(fontSize: 11.8, color: c.textSecondary),
            ),
            const SizedBox(height: 10),

            // Simulated Android Wallpaper Backdrop + Official 28dp Material 3 Widget Frame
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0E1310)
                    : const Color(0xFFE9F3EC),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: strokeColor, width: 1),
                  boxShadow: isDark
                      ? const []
                      : [
                          BoxShadow(
                            color: const Color(
                              0xFF101828,
                            ).withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: widgetPreview,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
