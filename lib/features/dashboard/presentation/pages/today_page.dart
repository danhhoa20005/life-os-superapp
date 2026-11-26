import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/behavior/behavior_domain.dart';
import '../../../../core/behavior/behavior_engine.dart';
import '../../../../core/behavior/local_behavior_store.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/voice_smart_capture_sheet.dart';
import '../../../app_update/presentation/widgets/app_update_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../budgets/presentation/bloc/budget_bloc.dart';
import '../../../calendar/presentation/bloc/calendar_bloc.dart';
import '../../../daily_life/domain/entities/daily_life_entities.dart';
import '../../../daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../tasks/domain/repositories/task_repository.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../../transactions/presentation/bloc/transaction_state.dart';
import '../../../vehicles/domain/entities/vehicle_entities.dart';
import '../../../vehicles/presentation/bloc/vehicle_bloc.dart';
import '../../domain/entities/dashboard_entities.dart';
import '../bloc/dashboard_bloc.dart';
import '../widgets/upcoming_schedule_cycle_card.dart';

export '../widgets/upcoming_schedule_cycle_card.dart';

class _ShortcutSpec {
  final String id;
  final String label;
  final IconData icon;
  final LifeOsAccentTone tone;
  final String route;
  final Key? tileKey;

  const _ShortcutSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.tone,
    required this.route,
    this.tileKey,
  });
}

class _InboxActionItem {
  final IconData icon;
  final LifeOsAccentTone tone;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;
  final String? quickActionLabel;
  final VoidCallback? onQuickAction;
  final bool isQuickActionBusy;

  const _InboxActionItem({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
    this.quickActionLabel,
    this.onQuickAction,
    this.isQuickActionBusy = false,
  });
}

/// Screen 01: Flagship UI/UX Pro Max Redesigned "Hôm nay" (`TodayPage`) —
/// Emerald Mesh Fintech Hero Card + Privacy Masking + 3-Tile Daily Pulse Bento +
/// Unified `LifeOS Inbox` + Honest Budget/Fund Bento + Customizable 4×2 Pinned Dock.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _showAllInbox = false;
  static const List<_ShortcutSpec> _allShortcuts = [
    _ShortcutSpec(
      id: 'bank_qr',
      label: 'Ngân hàng & QR',
      icon: Icons.qr_code_2_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/notifications-privacy',
    ),
    _ShortcutSpec(
      id: 'vehicles',
      label: 'Xe máy',
      icon: Icons.two_wheeler_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/assets',
    ),
    _ShortcutSpec(
      id: 'health',
      label: 'Sức khỏe',
      icon: Icons.favorite_outline_rounded,
      tone: LifeOsAccentTone.coral,
      route: '/health-hub',
      tileKey: Key('home_tile_health'),
    ),
    _ShortcutSpec(
      id: 'kitchen',
      label: 'Bếp & Đi chợ',
      icon: Icons.shopping_basket_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/kitchen-groceries',
      tileKey: Key('home_tile_kitchen'),
    ),
    _ShortcutSpec(
      id: 'evn',
      label: 'Điện nước',
      icon: Icons.electric_bolt_rounded,
      tone: LifeOsAccentTone.amber,
      route: '/home-living',
      tileKey: Key('home_tile_evn'),
    ),
    _ShortcutSpec(
      id: 'documents',
      label: 'Tài liệu',
      icon: Icons.folder_open_rounded,
      tone: LifeOsAccentTone.amber,
      route: '/family-documents',
    ),
    _ShortcutSpec(
      id: 'notes_salary',
      label: 'Lương & Thuế',
      icon: Icons.request_quote_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/smart-notes-hub',
    ),
    _ShortcutSpec(
      id: 'settings',
      label: 'Cài đặt',
      icon: Icons.settings_outlined,
      tone: LifeOsAccentTone.neutral,
      route: '/settings-hub',
    ),
    _ShortcutSpec(
      id: 'habits',
      label: 'Thói quen',
      icon: Icons.local_fire_department_outlined,
      tone: LifeOsAccentTone.amber,
      route: '/habits-focus',
    ),
    _ShortcutSpec(
      id: 'wealth',
      label: 'Lãi vay & Bill',
      icon: Icons.calculate_outlined,
      tone: LifeOsAccentTone.blue,
      route: '/wealth-tools',
    ),
    _ShortcutSpec(
      id: 'widgets',
      label: 'Widget màn hình',
      icon: Icons.widgets_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/home-widgets',
    ),
    _ShortcutSpec(
      id: 'gemini_ai',
      label: 'Ghi thông minh',
      icon: Icons.bolt_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/financial-ai',
      tileKey: Key('home_tile_gemini_ai'),
    ),
    _ShortcutSpec(
      id: 'automation',
      label: 'Tự động hóa',
      icon: Icons.auto_awesome_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/automation-studio',
      tileKey: Key('home_tile_automation'),
    ),
  ];

  final Set<String> _pinnedIds = <String>{
    'bank_qr',
    'vehicles',
    'health',
    'kitchen',
    'evn',
    'documents',
    'notes_salary',
    'settings',
  };

  bool _hideBalances = false;
  bool _isSyncingHideBalances = false;
  bool _firstActionTipDismissed = false;
  bool _didInitialDependencySync = false;
  String? _hydratedUserId;
  PersonalizationSettings _personalizationSettings =
      const PersonalizationSettings();
  List<HabitShortcut> _habits = const <HabitShortcut>[];
  final Set<String> _sessionDismissedRecIds = <String>{};
  final Set<String> _approvingProvisionalIds = <String>{};

  @override
  void initState() {
    super.initState();
    _hydrateUserPrefs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isTickerEnabled = TickerMode.valuesOf(context).enabled;
    final isCurrentRoute = ModalRoute.isCurrentOf(context) ?? true;
    String? currentUid;
    try {
      currentUid = context.read<AuthBloc>().state.user?.id;
    } catch (_) {}
    if (!_didInitialDependencySync) {
      _didInitialDependencySync = true;
      _hydratedUserId = currentUid;
    } else if (_hydratedUserId != currentUid) {
      _hydratedUserId = currentUid;
      _sessionDismissedRecIds.clear();
      _hydrateUserPrefs();
    }
    if (isTickerEnabled && isCurrentRoute) {
      _syncHideBalancesFromPrefs();
    }
  }

  @override
  void didUpdateWidget(covariant TodayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncHideBalancesFromPrefs();
  }

  void _syncHideBalancesFromPrefs() {
    if (_isSyncingHideBalances) return;
    _isSyncingHideBalances = true;
    UserBehaviorPrefs.loadHideBalances().then((savedHide) {
      _isSyncingHideBalances = false;
      if (!mounted || savedHide == _hideBalances) return;
      setState(() => _hideBalances = savedHide);
    });
  }

  Future<void> _hydrateUserPrefs() async {
    await UserBehaviorPrefs.loadLastWalletId();
    final loadedHabits = await UserBehaviorPrefs.loadHabitShortcuts();
    final savedPinned = await UserBehaviorPrefs.loadPinnedShortcuts();
    final savedHide = await UserBehaviorPrefs.loadHideBalances();
    final tipDismissed = await UserBehaviorPrefs.loadFirstActionTipDismissed();
    final prefEnabled = await UserBehaviorPrefs.loadPersonalizationEnabled();
    final prefInterests = await UserBehaviorPrefs.loadUserInterests();
    var settings = await LocalBehaviorStore.instance.loadSettings();
    final parsedInterests = UserInterestGroup.fromIds(prefInterests);
    settings = settings.copyWith(
      enabled: prefEnabled,
      selectedInterests: parsedInterests.isNotEmpty
          ? Set<UserInterestGroup>.unmodifiable(parsedInterests)
          : settings.selectedInterests,
    );
    if (!mounted) return;
    setState(() {
      if (savedPinned != null) {
        _pinnedIds
          ..clear()
          ..addAll(savedPinned);
      }
      _hideBalances = savedHide;
      _firstActionTipDismissed = tipDismissed;
      _personalizationSettings = settings;
      _habits = loadedHabits;
    });
  }

  Future<void> _approveProvisionalTx(
    BuildContext context, {
    required String userId,
    required TransactionEntity tx,
  }) async {
    if (_approvingProvisionalIds.contains(tx.id)) return;
    final actionBloc = context.read<TransactionActionBloc>();
    if (actionBloc.state.status == ActionStatus.submitting) return;

    setState(() => _approvingProvisionalIds.add(tx.id));
    try {
      final waiter = actionBloc.stream
          .firstWhere(
            (s) =>
                s.status == ActionStatus.success ||
                s.status == ActionStatus.failure,
          )
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () =>
                const TransactionActionState(status: ActionStatus.failure),
          );
      actionBloc.add(
        ProvisionalTransactionDecisionSubmitted(
          userId: userId,
          transactionId: tx.id,
          approve: true,
        ),
      );
      final outcome = await waiter;
      if (!mounted) return;
      if (outcome.status == ActionStatus.success) {
        LifeOsTopToast.show(
          this.context,
          outcome.successMessage ?? 'Đã duyệt giao dịch ${tx.merchant}.',
          kind: LifeOsToastKind.success,
        );
      } else {
        LifeOsTopToast.show(
          this.context,
          outcome.failure?.message ??
              'Không thể duyệt giao dịch ${tx.merchant} — vui lòng thử lại.',
          kind: LifeOsToastKind.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _approvingProvisionalIds.remove(tx.id));
      } else {
        _approvingProvisionalIds.remove(tx.id);
      }
    }
  }

  String _fmtMoney(int minor, {String prefix = ''}) {
    if (_hideBalances) return '$prefix•••••••• ₫';
    return '$prefix${VndAmount.format(minor)}';
  }

  static String _weekdayVi(int weekday) => switch (weekday) {
    DateTime.monday => 'Hai',
    DateTime.tuesday => 'Ba',
    DateTime.wednesday => 'Tư',
    DateTime.thursday => 'Năm',
    DateTime.friday => 'Sáu',
    DateTime.saturday => 'Bảy',
    _ => 'Chủ nhật',
  };

  static String _formatDateVi(DateTime dt) {
    if (dt.weekday == DateTime.sunday) {
      return 'Chủ nhật, ${dt.day} tháng ${dt.month}';
    }
    return 'Thứ ${_weekdayVi(dt.weekday)}, ${dt.day} tháng ${dt.month}';
  }

  void _showCustomizeShortcutsSheet(BuildContext context) {
    final c = TammySemanticColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModal) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ghim tiện ích yêu thích trên Trang chủ',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allShortcuts.map((item) {
                    final selected = _pinnedIds.contains(item.id);
                    return FilterChip(
                      selected: selected,
                      avatar: LifeOsIconSquircle(
                        icon: item.icon,
                        tone: item.tone,
                        size: 22,
                        iconSize: 13,
                      ),
                      label: Text(item.label),
                      onSelected: (val) {
                        if (!val && _pinnedIds.length <= 4) {
                          LifeOsTopToast.show(
                            ctx,
                            'Vui lòng giữ tối thiểu 4 tiện ích trên Trang chủ.',
                            kind: LifeOsToastKind.warning,
                          );
                          return;
                        }
                        setState(() {
                          if (val) {
                            _pinnedIds.add(item.id);
                          } else {
                            _pinnedIds.remove(item.id);
                          }
                          _personalizationSettings = _personalizationSettings
                              .copyWith(
                                pinnedFeatureIds: List<String>.unmodifiable(
                                  _pinnedIds,
                                ),
                              );
                        });
                        UserBehaviorPrefs.savePinnedShortcuts(_pinnedIds);
                        BehaviorEventCollector().recordType(
                          val
                              ? BehaviorEventType.shortcutPinned
                              : BehaviorEventType.shortcutUnpinned,
                          metadata: <String, Object?>{
                            'targetId': item.id,
                            'featureKey': item.id,
                          },
                        );
                        setModal(() {});
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<ScoredRecommendation> _computeRecommendations({
    required BehaviorContextSignal signal,
    required List<TransactionEntity> provisionalTxs,
    required List<TaskEntity> openTasks,
    required List<TaskEntity> overdueTasks,
    required int upcomingEventCount,
    required List<VehicleEntity> dueVehicles,
    required List<RecurringBillEntity> dueBills,
    required bool hasConfiguredBudget,
    required int spentPct,
  }) {
    if (!_personalizationSettings.enabled) {
      return const <ScoredRecommendation>[];
    }

    final effectiveSettings = _personalizationSettings.copyWith(
      pinnedFeatureIds: List<String>.unmodifiable(_pinnedIds),
    );

    final candidates = <RecommendationCandidate>[
      if (provisionalTxs.isNotEmpty)
        RecommendationCandidate(
          id: 'ctx_provisional_tx',
          featureKey: 'auto_tx_review',
          titleVi: 'Kiểm tra ${provisionalTxs.length} giao dịch chờ duyệt',
          subtitleVi: 'Xác nhận trước khi cộng vào sổ thu chi.',
          reasonVi: 'Có giao dịch mới từ thông báo ngân hàng',
          targetRoute: '/auto-tx-review',
          actionLabelVi: 'Xem & duyệt',
          interestGroup: UserInterestGroup.spending,
          urgencyScore: 0.95,
          habitConsistencyScore: 0.5,
          isFinancialMutation: true,
          isStarterSuggestion: false,
        ),
      if (openTasks.isNotEmpty)
        RecommendationCandidate(
          id: 'ctx_open_tasks',
          featureKey: 'tasks_board',
          titleVi: overdueTasks.isNotEmpty
              ? 'Xử lý ${overdueTasks.length} việc quá hạn'
              : 'Rà soát ${openTasks.length} việc cần làm',
          subtitleVi: 'Mở bảng việc để sắp xếp thứ tự ưu tiên.',
          reasonVi: overdueTasks.isNotEmpty
              ? 'Có công việc đã quá hạn cần chú ý'
              : 'Phù hợp nhịp lập kế hoạch trong ngày',
          targetRoute: '/tasks-board',
          actionLabelVi: 'Mở bảng việc',
          interestGroup: UserInterestGroup.schedule,
          urgencyScore: overdueTasks.isNotEmpty ? 0.90 : 0.65,
          isFinancialMutation: false,
          isStarterSuggestion: true,
        ),
      if (upcomingEventCount > 0)
        RecommendationCandidate(
          id: 'ctx_upcoming_schedule',
          featureKey: 'planning_schedule',
          titleVi: 'Xem $upcomingEventCount lịch hẹn sắp tới',
          subtitleVi: 'Kiểm tra khung giờ rảnh và nhắc nhở quan trọng.',
          reasonVi: 'Có lịch hẹn sắp diễn ra',
          targetRoute: '/planning',
          actionLabelVi: 'Xem lịch trình',
          interestGroup: UserInterestGroup.schedule,
          urgencyScore: 0.65,
          isFinancialMutation: false,
          isStarterSuggestion: true,
        ),
      if (hasConfiguredBudget &&
          (signal.budgetUsageRatio >= 0.75 || signal.isEndOfMonth))
        RecommendationCandidate(
          id: 'ctx_budget_review',
          featureKey: 'finance_report',
          titleVi: 'Theo dõi ngân sách tháng ($spentPct%)',
          subtitleVi: 'Xem chi tiết các khoản chi để cân đối cuối tháng.',
          reasonVi: signal.budgetUsageRatio >= 0.85
              ? 'Mức chi đã chạm $spentPct% hạn mức tháng'
              : 'Cuối tháng là lúc rà soát ngân sách',
          targetRoute: '/finance-report',
          actionLabelVi: 'Xem báo cáo',
          interestGroup: UserInterestGroup.spending,
          urgencyScore: signal.budgetUsageRatio >= 0.85 ? 0.88 : 0.60,
          isFinancialMutation: false,
          isStarterSuggestion: false,
        ),
      if (dueBills.isNotEmpty || signal.isEndOfMonth)
        RecommendationCandidate(
          id: 'ctx_utilities_bills',
          featureKey: 'home_living_evn',
          titleVi: dueBills.isNotEmpty
              ? 'Kiểm tra ${dueBills.length} hóa đơn sắp đến hạn'
              : 'Kiểm tra chỉ số điện nước EVN',
          subtitleVi: 'Theo dõi bậc thang điện và hóa đơn định kỳ.',
          reasonVi: dueBills.isNotEmpty
              ? 'Có hóa đơn đến hạn trong 7 ngày tới'
              : 'Cuối tháng phù hợp chốt số điện nước',
          targetRoute: '/home-living',
          actionLabelVi: 'Mở tiện ích nhà',
          interestGroup: UserInterestGroup.home,
          urgencyScore: dueBills.isNotEmpty ? 0.85 : 0.50,
          isFinancialMutation: false,
          isStarterSuggestion: true,
        ),
      if (dueVehicles.isNotEmpty || signal.isWeekend)
        RecommendationCandidate(
          id: 'ctx_vehicle_care',
          featureKey: 'vehicles_assets',
          titleVi: dueVehicles.isNotEmpty
              ? 'Bảo dưỡng xe ${dueVehicles.first.name}'
              : 'Kiểm tra sổ xe & lịch bảo dưỡng',
          subtitleVi: 'Cập nhật ODO và hạn bảo hiểm xe an toàn.',
          reasonVi: dueVehicles.isNotEmpty
              ? 'Xe sắp đến mốc bảo dưỡng định kỳ'
              : 'Cuối tuần thuận tiện kiểm tra xe cộ',
          targetRoute: '/assets',
          actionLabelVi: 'Mở xe cộ',
          interestGroup: UserInterestGroup.vehicle,
          urgencyScore: dueVehicles.isNotEmpty ? 0.85 : 0.45,
          isFinancialMutation: false,
          isStarterSuggestion: true,
        ),
      if (signal.hasActiveFamily || signal.isWeekend)
        RecommendationCandidate(
          id: 'ctx_family_space',
          featureKey: 'family_space',
          titleVi: signal.hasActiveFamily
              ? 'Xem quỹ & chia tiền gia đình'
              : 'Tìm hiểu không gian gia đình',
          subtitleVi: 'Quản lý quỹ chung minh bạch, tách bạch ví riêng.',
          reasonVi: signal.isWeekend
              ? 'Cuối tuần phù hợp tổng kết sinh hoạt gia đình'
              : 'Nhóm gia đình đang hoạt động',
          targetRoute: '/family',
          actionLabelVi: 'Mở gia đình',
          interestGroup: UserInterestGroup.family,
          urgencyScore: 0.48,
          isFinancialMutation: false,
          isStarterSuggestion: true,
        ),
    ];

    if (!effectiveSettings.isColdStart) {
      for (final habit in _habits.take(4)) {
        candidates.add(
          RecommendationCandidate.fromHabitShortcut(
            habit,
            isPinnedByUser: _pinnedIds.contains(habit.id),
            isFinancialMutation: true,
          ),
        );
      }
    }

    candidates.addAll(
      RecommendationEngine.coldStartStarterSuggestions(
        settings: effectiveSettings,
        signal: signal,
      ),
    );

    final seenIds = <String>{};
    final deduped = <RecommendationCandidate>[];
    for (final item in candidates) {
      if (_sessionDismissedRecIds.contains(item.id)) continue;
      final lastDismissMs =
          effectiveSettings.lastDismissedEpochMs[item.id] ?? 0;
      if (lastDismissMs > 0 &&
          signal.now.millisecondsSinceEpoch - lastDismissMs < 86400000) {
        continue;
      }
      if (seenIds.add(item.id)) {
        deduped.add(item);
      }
    }

    return RecommendationEngine.recommend(
      candidates: deduped,
      settings: effectiveSettings,
      signal: signal,
      limit: 2,
    );
  }

  void _handleRecommendationTap(
    BuildContext context,
    ScoredRecommendation rec,
  ) {
    FeedbackEngine()
        .recordRecommendationAccepted(
          rec.candidate.id,
          featureKey: rec.candidate.featureKey,
        )
        .then((updated) {
          if (mounted) {
            setState(() => _personalizationSettings = updated);
          }
        });

    final prefill = rec.candidate.prefillText;
    if (prefill != null && prefill.isNotEmpty) {
      showVoiceSmartCaptureSheet(
        context,
        autoStartListening: false,
        initialTranscript: prefill,
      );
      return;
    }

    final route = rec.candidate.targetRoute;
    if (route == '/today' ||
        route == '/finance' ||
        route == '/planning' ||
        route == '/family') {
      context.go(route);
    } else {
      context.push(route);
    }
  }

  void _handleRecommendationDismiss(ScoredRecommendation rec) {
    setState(() {
      _sessionDismissedRecIds.add(rec.candidate.id);
    });
    FeedbackEngine()
        .recordRecommendationDismissed(
          rec.candidate.id,
          featureKey: rec.candidate.featureKey,
        )
        .then((updated) {
          if (mounted) {
            setState(() => _personalizationSettings = updated);
          }
        });
  }

  void _showPersonalizationSettingsSheet(BuildContext context) {
    final c = TammySemanticColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final enabled = _personalizationSettings.enabled;
            final selectedGroups = _personalizationSettings.selectedInterests;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tùy chỉnh gợi ý thông minh',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mọi phân tích đều chạy cục bộ trên thiết bị, không gửi dữ liệu cá nhân ra ngoài.',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12.2,
                      height: 1.35,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const Key('personalization_enable_switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Bật gợi ý thông minh',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      'Hiển thị tối đa 2 gợi ý phù hợp nhịp sinh hoạt.',
                      softWrap: true,
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                    value: enabled,
                    onChanged: (val) async {
                      final next = _personalizationSettings.copyWith(
                        enabled: val,
                      );
                      setState(() => _personalizationSettings = next);
                      setModal(() {});
                      await UserBehaviorPrefs.savePersonalizationEnabled(val);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Nhóm quan tâm',
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
                    children: UserInterestGroup.values.map((group) {
                      final isSelected = selectedGroups.contains(group);
                      return FilterChip(
                        key: Key('personalization_interest_${group.id}'),
                        selected: isSelected,
                        label: Text(group.shortLabelVi),
                        onSelected: (val) async {
                          final nextGroups = Set<UserInterestGroup>.from(
                            selectedGroups,
                          );
                          if (group == UserInterestGroup.all) {
                            nextGroups
                              ..clear()
                              ..add(UserInterestGroup.all);
                          } else {
                            nextGroups.remove(UserInterestGroup.all);
                            if (val) {
                              nextGroups.add(group);
                            } else {
                              nextGroups.remove(group);
                            }
                            if (nextGroups.isEmpty) {
                              nextGroups.add(UserInterestGroup.all);
                            }
                          }
                          final immutableGroups =
                              Set<UserInterestGroup>.unmodifiable(nextGroups);
                          setState(() {
                            _personalizationSettings = _personalizationSettings
                                .copyWith(selectedInterests: immutableGroups);
                          });
                          setModal(() {});
                          await UserBehaviorPrefs.saveUserInterests(
                            immutableGroups.map((e) => e.id).toSet(),
                          );
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('personalization_reset_btn'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        foregroundColor: c.error,
                        side: BorderSide(
                          color: c.error.withValues(alpha: 0.45),
                        ),
                      ),
                      icon: const Icon(Icons.restart_alt_rounded, size: 19),
                      label: const Text(
                        'Đặt lại dữ liệu hành vi',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: ctx,
                          builder: (dlgCtx) => AlertDialog(
                            title: const Text('Đặt lại dữ liệu hành vi?'),
                            content: const Text(
                              'Xóa thói quen đã học, bộ đếm ẩn gợi ý và nhóm quan tâm của tài khoản hiện tại. Ví, số dư và mã PIN vẫn được giữ nguyên.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dlgCtx).pop(false),
                                child: const Text('Hủy'),
                              ),
                              FilledButton(
                                key: const Key(
                                  'personalization_reset_confirm_btn',
                                ),
                                onPressed: () => Navigator.of(dlgCtx).pop(true),
                                child: const Text('Đặt lại'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        await UserBehaviorPrefs.resetAllBehaviorDataForActiveUser();
                        if (!mounted) return;
                        setState(() {
                          _personalizationSettings =
                              const PersonalizationSettings();
                          _habits = const <HabitShortcut>[];
                          _sessionDismissedRecIds.clear();
                          _firstActionTipDismissed = false;
                        });
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                        if (mounted) {
                          LifeOsTopToast.show(
                            this.context,
                            'Đã đặt lại dữ liệu hành vi cho tài khoản này.',
                            kind: LifeOsToastKind.success,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static final DateFormat _timeFmt = DateFormat('HH:mm');
  static final DateFormat _dateIsoFmt = DateFormat('yyyy-MM-dd');
  static final DateFormat _dayMonthFmt = DateFormat('dd/MM');

  void _togglePrivacy() {
    final nextHide = !_hideBalances;
    setState(() => _hideBalances = nextHide);
    UserBehaviorPrefs.saveHideBalances(nextHide);
    LifeOsTopToast.show(
      context,
      nextHide
          ? 'Đã bật chế độ ẩn số dư riêng tư.'
          : 'Đã hiển thị lại số dư tài chính.',
      kind: LifeOsToastKind.info,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const LifeOsTopBrandHeader(title: 'LifeOS'),
              const _TodayGreetingHeaderStrip(),
              Expanded(
                child: BlocBuilder<DashboardBloc, DashboardState>(
                  buildWhen: (prev, next) =>
                      (prev.isLoading &&
                              prev.data == TodayDashboardEntity.empty) !=
                          (next.isLoading &&
                              next.data == TodayDashboardEntity.empty) ||
                      (prev.failure != null &&
                              prev.data == TodayDashboardEntity.empty) !=
                          (next.failure != null &&
                              next.data == TodayDashboardEntity.empty),
                  builder: (context, state) {
                    if (state.isLoading &&
                        state.data == TodayDashboardEntity.empty) {
                      return Semantics(
                        container: true,
                        label: 'Đang tải tổng quan hôm nay',
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            8,
                            AppSpacing.md,
                            104,
                          ),
                          children: const [
                            LifeOsSkeletonBox(height: 156, borderRadius: 18),
                            SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: LifeOsSkeletonBox(
                                    height: 92,
                                    borderRadius: 18,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: LifeOsSkeletonBox(
                                    height: 92,
                                    borderRadius: 18,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            LifeOsSkeletonBox(height: 110, borderRadius: 18),
                          ],
                        ),
                      );
                    }
                    if (state.failure != null &&
                        state.data == TodayDashboardEntity.empty) {
                      return ErrorRetryView(
                        message: state.failure!.message,
                        onRetry: () {
                          final user = context.read<AuthBloc>().state.user;
                          if (user != null) {
                            context.read<DashboardBloc>().add(
                              DashboardWatchStarted(
                                userId: user.id,
                                familyId: user.activeFamilyId,
                              ),
                            );
                          }
                        },
                      );
                    }

                    final pinnedSpecs = _allShortcuts
                        .where((s) => _pinnedIds.contains(s.id))
                        .toList();

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppSpacing.maxContentWidth,
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            4,
                            AppSpacing.md,
                            104,
                          ),
                          itemCount: 7,
                          itemBuilder: (context, index) => switch (index) {
                            0 => const AppUpdateBanner(),
                            1 => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _TodayMintSummarySection(
                                formatDateVi: _formatDateVi,
                                dateIsoFmt: _dateIsoFmt,
                              ),
                            ),
                            2 => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _TodayScheduleAndSpendRow(
                                fmtMoney: _fmtMoney,
                              ),
                            ),
                            3 => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _TodayWealthHeroSection(
                                hideBalances: _hideBalances,
                                onTogglePrivacy: _togglePrivacy,
                                fmtMoney: _fmtMoney,
                              ),
                            ),
                            4 => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _TodayInboxSection(
                                showAllInbox: _showAllInbox,
                                onToggleShowAll: () => setState(
                                  () => _showAllInbox = !_showAllInbox,
                                ),
                                approvingProvisionalIds:
                                    _approvingProvisionalIds,
                                onApproveProvisional: _approveProvisionalTx,
                                fmtMoney: _fmtMoney,
                                timeFmt: _timeFmt,
                                dateIsoFmt: _dateIsoFmt,
                                dayMonthFmt: _dayMonthFmt,
                              ),
                            ),
                            5 => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _TodayShortcutsSection(
                                pinnedSpecs: pinnedSpecs,
                                onCustomize: () =>
                                    _showCustomizeShortcutsSheet(context),
                              ),
                            ),
                            _ => Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _TodayQuickHubRow(),
                                const SizedBox(height: 8),
                                _TodayRecommendationsCardSection(
                                  personalizationSettings:
                                      _personalizationSettings,
                                  firstActionTipDismissed:
                                      _firstActionTipDismissed,
                                  onDismissFirstActionTip: () async {
                                    setState(
                                      () => _firstActionTipDismissed = true,
                                    );
                                    await UserBehaviorPrefs.saveFirstActionTipDismissed(
                                      true,
                                    );
                                  },
                                  onOpenSettings: () =>
                                      _showPersonalizationSettingsSheet(
                                        context,
                                      ),
                                  computeRecommendations:
                                      _computeRecommendations,
                                  onRecommendationTap: (rec) =>
                                      _handleRecommendationTap(context, rec),
                                  onRecommendationDismiss:
                                      _handleRecommendationDismiss,
                                ),
                              ],
                            ),
                          },
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

class _TodayGreetingHeaderStrip extends StatelessWidget {
  const _TodayGreetingHeaderStrip();

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final fullName = context.select((AuthBloc b) => b.state.user?.fullName);
    final firstName = (fullName ?? 'bạn').trim().split(' ').last;
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 2, AppSpacing.md, 2),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.maxContentWidth,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Xin chào, $firstName',
                          style: TextStyle(
                            fontSize: 18.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            height: 1.12,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          UserBehaviorPrefs.contextualTimeSubtitle(now),
                          style: TextStyle(
                            fontSize: 11.4,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: c.primarySubtle,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  side: BorderSide(
                    color: c.primary.withValues(alpha: 0.28),
                    width: 0.9,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const Key('today_open_gemini_ai_pill'),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  onTap: () => context.push('/financial-ai'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 5.5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BananaGlassIcon(
                          assetPath: AppAssets.ic3dAiSpark,
                          fallbackIcon: Icons.auto_awesome_rounded,
                          size: 20,
                          borderRadius: 6.5,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Ghi nhanh',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: c.primary,
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
      ),
    );
  }
}

class _TodayMintSummarySection extends StatelessWidget {
  final String Function(DateTime) formatDateVi;
  final DateFormat dateIsoFmt;

  const _TodayMintSummarySection({
    required this.formatDateVi,
    required this.dateIsoFmt,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    final openTasksCount = context.select(
      (DashboardBloc b) => b.state.data.openTasksCount,
    );
    final monthlyExpenseMinor = context.select(
      (DashboardBloc b) => b.state.data.monthlyExpenseMinor,
    );
    final calEvents = context.select((CalendarBloc b) => b.state.events);
    final allTasks = context.select((TaskBloc b) => b.state.tasks);
    final budgets = context.select((BudgetBloc b) => b.state.budgets);
    final allTransactions = context.select(
      (TransactionListBloc b) => b.state.allTransactions,
    );
    final vehicles = context.select((VehicleBloc b) => b.state.vehicles);
    final bills = context.select((VehicleBloc b) => b.state.bills);

    final (medications, hasActiveHydration) = context.select((
      DailyLifeBloc? b,
    ) {
      if (b == null) {
        return (const <MedicationCabinetItemEntity>[], false);
      }
      final snap = b.state.snapshot;
      return (
        snap.medications,
        snap.hydration.reminderEnabled && !snap.hydration.isGoalReached,
      );
    });

    final upcomingEvents =
        calEvents.where((e) => !e.endsAt.isBefore(now)).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final todayEvents = upcomingEvents
        .where((e) => !e.startsAt.isAfter(endOfToday))
        .toList();
    final futureEvents = upcomingEvents
        .where((e) => e.startsAt.isAfter(endOfToday))
        .toList();

    final provisionalTxs = allTransactions
        .where(
          (t) =>
              t.verification == TransactionVerification.provisional &&
              !t.isReversed,
        )
        .toList();
    final openTasks = allTasks
        .where((t) => t.status != TaskWorkflowStatus.done)
        .toList();
    final dueVehicles = vehicles
        .where((v) => v.dueStateAt(now) != VehicleDueState.healthy)
        .toList();
    final dueBills = bills
        .where((b) => b.nextDueDate.difference(now).inDays <= 7)
        .toList();

    final todayIso = dateIsoFmt.format(now);
    final dueMedsToday = medications
        .where(
          (item) => item.slot.isScheduledDaily && !item.isTakenOn(todayIso),
        )
        .toList();

    final totalBudgetLimit = budgets.fold<int>(
      0,
      (sum, b) => sum + b.limitMinor,
    );
    final hasConfiguredBudget = totalBudgetLimit > 0;
    final spentPct = hasConfiguredBudget
        ? ((monthlyExpenseMinor * 100) / totalBudgetLimit).clamp(0, 999).round()
        : 0;

    final inboxCount =
        (provisionalTxs.isNotEmpty ? 1 : 0) +
        ((todayEvents.isNotEmpty || futureEvents.isNotEmpty) ? 1 : 0) +
        (openTasks.isNotEmpty ? 1 : 0) +
        (dueVehicles.isNotEmpty ? 1 : 0) +
        (dueBills.isNotEmpty ? 1 : 0) +
        (dueMedsToday.isNotEmpty ? 1 : 0) +
        (hasActiveHydration ? 1 : 0) +
        (hasConfiguredBudget && spentPct >= 85 ? 1 : 0);

    void onTapNeedAttention() {
      if (provisionalTxs.isNotEmpty) {
        context.push('/auto-tx-review', extra: provisionalTxs.first);
      } else if (todayEvents.isNotEmpty) {
        context.push('/event-detail', extra: todayEvents.first);
      } else if (futureEvents.isNotEmpty) {
        context.push('/event-detail', extra: futureEvents.first);
      } else if (openTasks.isNotEmpty) {
        context.push('/tasks-board');
      } else if (dueVehicles.isNotEmpty || dueBills.isNotEmpty) {
        context.push('/assets');
      } else if (dueMedsToday.isNotEmpty) {
        context.push('/health-hub');
      } else if (hasActiveHydration) {
        context.push('/health-hub?tab=water');
      } else if (hasConfiguredBudget && spentPct >= 85) {
        context.go('/finance');
      } else {
        context.push('/activity-notifications');
      }
    }

    // Keep unused local referenced cleanly for readability
    assert(startOfToday.year == now.year);

    return LifeOsMintHeroCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const LifeOsIconSquircle(
                icon: Icons.calendar_today_rounded,
                tone: LifeOsAccentTone.emerald,
                size: 26,
                iconSize: 14,
              ),
              const SizedBox(width: 8),
              Text(
                'Hôm nay',
                style: TextStyle(
                  fontSize: 13.8,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatDateVi(now),
                      style: TextStyle(
                        fontSize: 11.8,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _TodayMintMetricColumn(
                    count: upcomingEvents.length,
                    label: 'Sự kiện',
                    valueColor: c.primary,
                    onTap: () => context.go('/planning'),
                  ),
                ),
                VerticalDivider(width: 16, thickness: 1, color: c.separator),
                Expanded(
                  child: _TodayMintMetricColumn(
                    count: openTasksCount,
                    label: 'Việc cần làm',
                    valueColor: c.primary,
                    onTap: () => context.push('/tasks-board'),
                  ),
                ),
                VerticalDivider(width: 16, thickness: 1, color: c.separator),
                Expanded(
                  child: _TodayMintMetricColumn(
                    count: inboxCount,
                    label: 'Cần xử lý',
                    valueColor: inboxCount > 0
                        ? const Color(0xFFD97706)
                        : c.primary,
                    onTap: onTapNeedAttention,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayScheduleAndSpendRow extends StatelessWidget {
  final String Function(int, {String prefix}) fmtMoney;

  const _TodayScheduleAndSpendRow({required this.fmtMoney});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final now = DateTime.now();
    final calEvents = context.select((CalendarBloc b) => b.state.events);
    final monthlyExpenseMinor = context.select(
      (DashboardBloc b) => b.state.data.monthlyExpenseMinor,
    );
    final budgets = context.select((BudgetBloc b) => b.state.budgets);

    final totalBudgetLimit = budgets.fold<int>(
      0,
      (sum, b) => sum + b.limitMinor,
    );
    final hasConfiguredBudget = totalBudgetLimit > 0;
    final spentPct = hasConfiguredBudget
        ? ((monthlyExpenseMinor * 100) / totalBudgetLimit).clamp(0, 999).round()
        : 0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: UpcomingScheduleCycleCard(
              cardKey: const Key('upcoming_schedule_cycle_card'),
              weekCount: UpcomingScheduleCycleCard.countUpcomingInWindow(
                calEvents,
                now,
                const Duration(days: 7),
              ),
              monthCount: UpcomingScheduleCycleCard.countUpcomingInWindow(
                calEvents,
                now,
                const Duration(days: 30),
              ),
              yearCount: UpcomingScheduleCycleCard.countUpcomingInWindow(
                calEvents,
                now,
                const Duration(days: 365),
              ),
              onLongPressOpenPlanning: (horizon) =>
                  context.go('/planning?view=${horizon.name}'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LifeOsSoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              borderRadius: 18,
              onTap: () => context.go('/finance'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const LifeOsIconSquircle(
                        icon: Icons.payments_outlined,
                        tone: LifeOsAccentTone.emerald,
                        size: 28,
                        iconSize: 15,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Chi tiêu tháng này',
                            style: TextStyle(
                              fontSize: 12.4,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 17,
                        color: c.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      fmtMoney(monthlyExpenseMinor),
                      style: TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      hasConfiguredBudget
                          ? '/ ${fmtMoney(totalBudgetLimit)}'
                          : 'Chưa đặt hạn mức',
                      style: TextStyle(
                        fontSize: 11.2,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: hasConfiguredBudget
                          ? (spentPct / 100).clamp(0.04, 1.0)
                          : 0.08,
                      backgroundColor: c.surfaceRaised,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        (hasConfiguredBudget && spentPct >= 85)
                            ? c.error
                            : c.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      hasConfiguredBudget
                          ? 'Đã chi $spentPct% ngân sách'
                          : 'Chạm để đặt hạn mức',
                      style: TextStyle(
                        fontSize: 10.8,
                        fontWeight: FontWeight.w600,
                        color: (hasConfiguredBudget && spentPct >= 85)
                            ? c.error
                            : c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayWealthHeroSection extends StatelessWidget {
  final bool hideBalances;
  final VoidCallback onTogglePrivacy;
  final String Function(int, {String prefix}) fmtMoney;

  const _TodayWealthHeroSection({
    required this.hideBalances,
    required this.onTogglePrivacy,
    required this.fmtMoney,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final d = context.select((DashboardBloc b) => b.state.data);
    final userFullName = context.select(
      (AuthBloc b) => b.state.user?.fullName ?? '',
    );
    final activeFamily = context.select((FamilyBloc b) => b.state.activeFamily);
    final gcalConnected = context.select(
      (CalendarBloc b) => b.state.isGoogleAuthorized,
    );
    final bankConnected = context.select(
      (NotificationIngestionBloc b) =>
          (b.state.consent?.enabled ?? false) ||
          b.state.linkedBankAccounts.isNotEmpty,
    );
    final budgets = context.select((BudgetBloc b) => b.state.budgets);
    final allTransactions = context.select(
      (TransactionListBloc b) => b.state.allTransactions,
    );

    final avatarNames = activeFamily != null && activeFamily.members.isNotEmpty
        ? activeFamily.members.map((m) => m.fullName).toList()
        : (userFullName.trim().isNotEmpty
              ? <String>[userFullName]
              : const <String>[]);

    final totalBudgetLimit = budgets.fold<int>(
      0,
      (sum, b) => sum + b.limitMinor,
    );
    final hasConfiguredBudget = totalBudgetLimit > 0;
    final confirmedTodayFromList = allTransactions
        .where(
          (t) =>
              t.isConfirmedInLedger &&
              !t.isReversed &&
              t.kind == TransactionKind.expense &&
              t.occurredAt.year == now.year &&
              t.occurredAt.month == now.month &&
              t.occurredAt.day == now.day,
        )
        .fold<int>(0, (sum, t) => sum + t.amountMinor);
    final todayExpenseMinor = d.todayExpenseMinor > 0
        ? d.todayExpenseMinor
        : confirmedTodayFromList;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final remainingDays = (daysInMonth - now.day + 1).clamp(1, 31);
    final remainingBudgetMinor = hasConfiguredBudget
        ? (totalBudgetLimit - d.monthlyExpenseMinor).clamp(0, totalBudgetLimit)
        : 0;
    final safeDailyMinor = hasConfiguredBudget
        ? (remainingBudgetMinor ~/ remainingDays)
        : 0;

    final hasExternalSync = gcalConnected || bankConnected;
    final syncStatusLabel = gcalConnected && bankConnected
        ? 'Đã nối Lịch & Ngân hàng'
        : gcalConnected
        ? 'Đã nối Google Calendar'
        : bankConnected
        ? 'Đã nối Ngân hàng'
        : 'Lưu cục bộ an toàn';

    return LifeOsAnimatedItemEntrance(
      key: const ValueKey('today_wealth_hero_entrance'),
      itemId: 'today_wealth_hero',
      staggerIndex: 0,
      child: ProHeroGradientCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const BananaGlassIcon(
                  assetPath: AppAssets.icNavFamily,
                  fallbackIcon: Icons.groups_rounded,
                  size: 30,
                  borderRadius: 9.5,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.go('/family'),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Quỹ gia đình & Tài sản',
                          style: TextStyle(
                            fontSize: 13.8,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: CircleBorder(
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.30),
                      width: 0.9,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const Key('toggle_balance_privacy_btn'),
                    customBorder: const CircleBorder(),
                    onTap: onTogglePrivacy,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      child: Center(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: Icon(
                          hideBalances
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => context.go('/family'),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 44,
                    ),
                    child: const Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: LifeOsTruthfulNumericText(
                          formattedValue: fmtMoney(d.netWorthMinor),
                          semanticsLabel: hideBalances
                              ? 'Tổng tài sản ròng đang ẩn riêng tư'
                              : 'Tổng tài sản ròng ${fmtMoney(d.netWorthMinor)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusPill,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.26),
                                width: 0.8,
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '↑ +${fmtMoney(d.monthlyIncomeMinor)} (thu tháng)',
                                style: const TextStyle(
                                  fontSize: 10.6,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB2F2BB),
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            key: const Key('today_hero_scope_pill'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusPill,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.24),
                                width: 0.8,
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    activeFamily != null
                                        ? Icons.groups_2_outlined
                                        : Icons.lock_outline_rounded,
                                    size: 11.5,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    activeFamily != null
                                        ? 'Ví riêng + Nhóm gia đình'
                                        : 'Ví cá nhân · Riêng tư',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (avatarNames.isNotEmpty)
                            LifeOsAvatarStack(
                              names: avatarNames,
                              radius: 12,
                              onAddTap: () => context.go('/family'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                RepaintBoundary(
                  child: CustomPaint(
                    foregroundPainter: const LiquidGlassRimPainter(
                      borderRadius: 16,
                      isDark: true,
                      accentRimColor: Color(0xFF8CE99A),
                      intensity: 1.2,
                    ),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        AppAssets.hero3dWealthVault,
                        width: 58,
                        height: 58,
                        cacheWidth: 174,
                        cacheHeight: 174,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.shield_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFFFFF), Color(0xFFE7F9EE)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        key: const Key('home_quick_expense_btn'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => showVoiceSmartCaptureSheet(
                          context,
                          autoStartListening: true,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 42),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  BananaGlassIcon(
                                    assetPath: AppAssets.ic3dVoiceAi,
                                    fallbackIcon: Icons.mic_rounded,
                                    size: 22,
                                    borderRadius: 7,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Nói ghi nhanh',
                                    style: TextStyle(
                                      fontSize: 12.8,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF065F28),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.32),
                        width: 1.0,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const Key('home_quick_schedule_btn'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => showLifeOsQuickCreateHub(context),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 42),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                BananaGlassIcon(
                                  assetPath: AppAssets.icNavCalendar,
                                  fallbackIcon: Icons.event_note_rounded,
                                  size: 22,
                                  borderRadius: 7,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Thêm lịch / việc',
                                  style: TextStyle(
                                    fontSize: 12.8,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LifeOsDetailsDiscloseSection(
              toggleKey: const Key('today_hero_details_toggle'),
              onDarkSurface: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ProGlassStatPill(
                          icon: Icons.south_west_rounded,
                          label: 'Thu tháng',
                          value: fmtMoney(d.monthlyIncomeMinor, prefix: '+'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ProGlassStatPill(
                          icon: Icons.north_east_rounded,
                          iconColor: const Color(0xFFFECACA),
                          label: 'Chi tháng',
                          value: fmtMoney(d.monthlyExpenseMinor, prefix: '-'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.24),
                        width: 0.9,
                      ),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Hôm nay chi: ${fmtMoney(todayExpenseMinor)}',
                          style: const TextStyle(
                            fontSize: 11.8,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (hasConfiguredBudget)
                          Text(
                            'Còn tiêu/ngày: ${fmtMoney(safeDailyMinor)}',
                            style: const TextStyle(
                              fontSize: 11.8,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB2F2BB),
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasExternalSync)
                              Container(
                                width: 6.5,
                                height: 6.5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF86EFAC),
                                  shape: BoxShape.circle,
                                ),
                              )
                            else
                              Icon(
                                Icons.shield_outlined,
                                size: 13,
                                color: Colors.white.withValues(alpha: 0.78),
                              ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                syncStatusLabel,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 11.2,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.88),
                                ),
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
          ],
        ),
      ),
    );
  }
}

class _TodayInboxSection extends StatelessWidget {
  final bool showAllInbox;
  final VoidCallback onToggleShowAll;
  final Set<String> approvingProvisionalIds;
  final Future<void> Function(
    BuildContext, {
    required String userId,
    required TransactionEntity tx,
  })
  onApproveProvisional;
  final String Function(int, {String prefix}) fmtMoney;
  final DateFormat timeFmt;
  final DateFormat dateIsoFmt;
  final DateFormat dayMonthFmt;

  const _TodayInboxSection({
    required this.showAllInbox,
    required this.onToggleShowAll,
    required this.approvingProvisionalIds,
    required this.onApproveProvisional,
    required this.fmtMoney,
    required this.timeFmt,
    required this.dateIsoFmt,
    required this.dayMonthFmt,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    final userId = context.select((AuthBloc b) => b.state.user?.id);
    final calEvents = context.select((CalendarBloc b) => b.state.events);
    final allTasks = context.select((TaskBloc b) => b.state.tasks);
    final budgets = context.select((BudgetBloc b) => b.state.budgets);
    final allTransactions = context.select(
      (TransactionListBloc b) => b.state.allTransactions,
    );
    final isTxActionSubmitting = context.select(
      (TransactionActionBloc b) => b.state.status == ActionStatus.submitting,
    );
    final vehicles = context.select((VehicleBloc b) => b.state.vehicles);
    final bills = context.select((VehicleBloc b) => b.state.bills);
    final monthlyExpenseMinor = context.select(
      (DashboardBloc b) => b.state.data.monthlyExpenseMinor,
    );

    DailyLifeBloc? dailyBloc;
    try {
      dailyBloc = BlocProvider.of<DailyLifeBloc>(context, listen: false);
    } catch (_) {}

    final (medications, activeHydration) = context.select((DailyLifeBloc? b) {
      if (b == null) {
        return (const <MedicationCabinetItemEntity>[], null);
      }
      final snap = b.state.snapshot;
      final hydrationAlert =
          snap.hydration.reminderEnabled && !snap.hydration.isGoalReached
          ? snap.hydration
          : null;
      return (snap.medications, hydrationAlert);
    });

    final upcomingEvents =
        calEvents.where((e) => !e.endsAt.isBefore(now)).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final todayEvents = upcomingEvents
        .where((e) => !e.startsAt.isAfter(endOfToday))
        .toList();
    final futureEvents = upcomingEvents
        .where((e) => e.startsAt.isAfter(endOfToday))
        .toList();

    final provisionalTxs = allTransactions
        .where(
          (t) =>
              t.verification == TransactionVerification.provisional &&
              !t.isReversed,
        )
        .toList();
    final openTasks = allTasks
        .where((t) => t.status != TaskWorkflowStatus.done)
        .toList();
    final overdueTasks = openTasks
        .where((t) => t.dueAt != null && t.dueAt!.isBefore(startOfToday))
        .toList();
    final dueVehicles = vehicles
        .where((v) => v.dueStateAt(now) != VehicleDueState.healthy)
        .toList();
    final dueBills = bills
        .where((b) => b.nextDueDate.difference(now).inDays <= 7)
        .toList();

    final todayIso = dateIsoFmt.format(now);
    final dueMedsToday = medications
        .where(
          (item) => item.slot.isScheduledDaily && !item.isTakenOn(todayIso),
        )
        .toList();

    final totalBudgetLimit = budgets.fold<int>(
      0,
      (sum, b) => sum + b.limitMinor,
    );
    final hasConfiguredBudget = totalBudgetLimit > 0;
    final spentPct = hasConfiguredBudget
        ? ((monthlyExpenseMinor * 100) / totalBudgetLimit).clamp(0, 999).round()
        : 0;

    final inboxItems = <_InboxActionItem>[
      if (provisionalTxs.isNotEmpty)
        _InboxActionItem(
          icon: Icons.account_balance_outlined,
          tone: LifeOsAccentTone.amber,
          title: '${provisionalTxs.length} giao dịch mới chờ xác nhận',
          subtitle:
              '${provisionalTxs.first.merchant} · ${fmtMoney(provisionalTxs.first.amountMinor)}',
          badge: 'Chờ duyệt',
          onTap: () =>
              context.push('/auto-tx-review', extra: provisionalTxs.first),
          quickActionLabel: userId != null ? 'Duyệt' : null,
          isQuickActionBusy:
              approvingProvisionalIds.contains(provisionalTxs.first.id) ||
              isTxActionSubmitting,
          onQuickAction: userId == null
              ? null
              : () => onApproveProvisional(
                  context,
                  userId: userId,
                  tx: provisionalTxs.first,
                ),
        ),
      if (todayEvents.isNotEmpty)
        _InboxActionItem(
          icon: Icons.event_available_rounded,
          tone: LifeOsAccentTone.emerald,
          title: todayEvents.first.title,
          subtitle:
              '${timeFmt.format(todayEvents.first.startsAt)} – ${timeFmt.format(todayEvents.first.endsAt)}${todayEvents.first.location != null && todayEvents.first.location!.isNotEmpty ? " · ${todayEvents.first.location}" : ""}',
          badge: 'Hôm nay',
          onTap: () => context.push('/event-detail', extra: todayEvents.first),
        )
      else if (futureEvents.isNotEmpty)
        _InboxActionItem(
          icon: Icons.calendar_month_rounded,
          tone: LifeOsAccentTone.blue,
          title: futureEvents.first.title,
          subtitle:
              '${dayMonthFmt.format(futureEvents.first.startsAt)} · ${timeFmt.format(futureEvents.first.startsAt)} – ${timeFmt.format(futureEvents.first.endsAt)}${futureEvents.first.location != null && futureEvents.first.location!.isNotEmpty ? " · ${futureEvents.first.location}" : ""}',
          badge: 'Sắp tới ${dayMonthFmt.format(futureEvents.first.startsAt)}',
          onTap: () => context.push('/event-detail', extra: futureEvents.first),
        ),
      if (openTasks.isNotEmpty)
        _InboxActionItem(
          icon: Icons.task_alt_rounded,
          tone: overdueTasks.isNotEmpty
              ? LifeOsAccentTone.coral
              : LifeOsAccentTone.blue,
          title: overdueTasks.isNotEmpty
              ? overdueTasks.first.title
              : openTasks.first.title,
          subtitle: overdueTasks.isNotEmpty
              ? 'Quá hạn ${overdueTasks.length} việc · Tổng còn ${openTasks.length} việc'
              : (openTasks.length > 1
                    ? 'Còn ${openTasks.length} việc cần làm'
                    : 'Chạm để mở việc cần làm'),
          badge: overdueTasks.isNotEmpty ? 'Quá hạn' : 'Việc làm',
          onTap: () => context.push('/tasks-board'),
          quickActionLabel: userId != null ? '✓ Xong' : null,
          onQuickAction: userId == null
              ? null
              : () {
                  final t = overdueTasks.isNotEmpty
                      ? overdueTasks.first
                      : openTasks.first;
                  if (t.status == TaskWorkflowStatus.proposed) {
                    context.read<TaskBloc>().add(
                      TaskResponseSubmitted(
                        RespondToTaskParams(
                          actorUserId: userId,
                          task: t,
                          accept: true,
                        ),
                      ),
                    );
                    LifeOsTopToast.show(context, 'Đã nhận việc "${t.title}".');
                  } else {
                    context.read<TaskBloc>().add(
                      TaskStatusChanged(
                        actorUserId: userId,
                        task: t,
                        nextStatus: TaskWorkflowStatus.done,
                      ),
                    );
                    LifeOsTopToast.show(context, 'Đã hoàn thành "${t.title}"!');
                  }
                },
        ),
      if (dueVehicles.isNotEmpty)
        _InboxActionItem(
          icon: dueVehicles.first.isMotorcycle
              ? Icons.two_wheeler_rounded
              : Icons.car_repair_rounded,
          tone: LifeOsAccentTone.coral,
          title: 'Bảo dưỡng xe: ${dueVehicles.first.name}',
          subtitle: 'Mốc tiếp theo: ${dueVehicles.first.nextDueKm} km',
          badge: 'Đến hạn',
          onTap: () => context.push('/assets'),
        ),
      if (dueBills.isNotEmpty)
        _InboxActionItem(
          icon: Icons.receipt_long_outlined,
          tone: LifeOsAccentTone.amber,
          title: 'Hóa đơn sắp đến hạn: ${dueBills.first.title}',
          subtitle: 'Dự kiến ${fmtMoney(dueBills.first.estimatedAmountMinor)}',
          badge: 'Hóa đơn',
          onTap: () => context.push('/assets'),
        ),
      if (dueMedsToday.isNotEmpty)
        _InboxActionItem(
          icon: Icons.medication_outlined,
          tone: LifeOsAccentTone.coral,
          title: 'Nhắc uống thuốc: ${dueMedsToday.first.name}',
          subtitle:
              '${dueMedsToday.first.dosage} · Lúc ${dueMedsToday.first.formattedReminderTime}',
          badge: 'Thuốc',
          onTap: () => context.push('/health-hub'),
          quickActionLabel: (userId != null && dailyBloc != null)
              ? '✓ Đã uống'
              : null,
          onQuickAction: (userId == null || dailyBloc == null)
              ? null
              : () {
                  dailyBloc!.add(
                    MedicationTakenToggled(
                      userId: userId,
                      item: dueMedsToday.first,
                    ),
                  );
                  LifeOsTopToast.show(
                    context,
                    'Đã đánh dấu uống "${dueMedsToday.first.name}".',
                  );
                },
        ),
      if (activeHydration != null)
        _InboxActionItem(
          icon: Icons.water_drop_outlined,
          tone: LifeOsAccentTone.blue,
          title:
              'Nhắc uống nước: ${activeHydration.waterMl}/${activeHydration.targetWaterMl} ml',
          subtitle: () {
            final nextWaterAt = activeHydration.nextReminderAt(now);
            final nextLabel = nextWaterAt != null
                ? 'Nhắc lúc ${timeFmt.format(nextWaterAt)}'
                : 'Mỗi ${activeHydration.intervalMinutes} phút';
            return '$nextLabel · Còn thiếu ${activeHydration.remainingMl} ml';
          }(),
          badge: 'Nước',
          onTap: () => context.push('/health-hub?tab=water'),
          quickActionLabel: (userId != null && dailyBloc != null)
              ? '+${activeHydration.preferredCupMl}ml'
              : null,
          onQuickAction: (userId == null || dailyBloc == null)
              ? null
              : () {
                  final cupMl = activeHydration.preferredCupMl;
                  dailyBloc!.add(
                    WaterIntakeLogged(
                      userId: userId,
                      deltaMl: cupMl,
                      targetWaterMl: activeHydration.targetWaterMl,
                    ),
                  );
                  LifeOsTopToast.show(
                    context,
                    'Đã ghi nhận +$cupMl ml nước uống.',
                  );
                },
        ),
      if (hasConfiguredBudget && spentPct >= 85)
        _InboxActionItem(
          icon: Icons.warning_amber_rounded,
          tone: LifeOsAccentTone.coral,
          title: 'Ngân sách tháng đã dùng $spentPct%',
          subtitle:
              '${fmtMoney(monthlyExpenseMinor)} / ${fmtMoney(totalBudgetLimit)}',
          badge: 'Ngân sách',
          onTap: () => context.go('/finance'),
        ),
    ];

    final visibleItems = showAllInbox
        ? inboxItems
        : inboxItems.take(4).toList();

    return LifeOsSoftCard(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LifeOsIconSquircle(
                icon: Icons.notifications_active_outlined,
                tone: LifeOsAccentTone.amber,
                size: 28,
                iconSize: 15,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Việc cần chú ý',
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 13.8,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ),
              if (inboxItems.isNotEmpty)
                LifeOsStatusPill(
                  label: '${inboxItems.length} mục',
                  tone: LifeOsAccentTone.emerald,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (inboxItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                    color: c.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chưa có việc gấp hôm nay.',
                      style: TextStyle(fontSize: 12.2, color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            for (var idx = 0; idx < visibleItems.length; idx++)
              _TodayInboxRow(
                item: visibleItems[idx],
                showDivider: idx > 0,
                separatorColor: c.separator,
              ),
            if (inboxItems.length > 4) ...[
              Divider(height: 14, color: c.separator),
              Center(
                child: TextButton.icon(
                  key: const Key('today_toggle_all_inbox_btn'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onToggleShowAll,
                  icon: Icon(
                    showAllInbox
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                  ),
                  label: Text(
                    showAllInbox
                        ? 'Thu gọn'
                        : 'Xem tất cả (${inboxItems.length} mục)',
                    style: const TextStyle(
                      fontSize: 12.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TodayInboxRow extends StatelessWidget {
  final _InboxActionItem item;
  final bool showDivider;
  final Color separatorColor;

  const _TodayInboxRow({
    required this.item,
    required this.showDivider,
    required this.separatorColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      children: [
        if (showDivider) Divider(height: 14, color: separatorColor),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: item.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                LifeOsIconSquircle(
                  icon: item.icon,
                  tone: item.tone,
                  size: 34,
                  iconSize: 17,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 13.4,
                          height: 1.24,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.28,
                          color: c.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 108),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child:
                        (item.onQuickAction != null ||
                                item.isQuickActionBusy) &&
                            item.quickActionLabel != null
                        ? FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              minimumSize: const Size(48, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                            ),
                            onPressed: item.isQuickActionBusy
                                ? null
                                : item.onQuickAction,
                            child: Text(
                              item.isQuickActionBusy
                                  ? 'Đang duyệt'
                                  : item.quickActionLabel!,
                              style: const TextStyle(
                                fontSize: 11.8,
                                fontWeight: FontWeight.w800,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          )
                        : LifeOsStatusPill(label: item.badge, tone: item.tone),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayShortcutsSection extends StatelessWidget {
  final List<_ShortcutSpec> pinnedSpecs;
  final VoidCallback onCustomize;

  const _TodayShortcutsSection({
    required this.pinnedSpecs,
    required this.onCustomize,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return LifeOsSoftCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Tiện ích của bạn',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        key: const Key('customize_home_shortcuts_btn'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(48, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: onCustomize,
                        child: const Text('Tùy chỉnh'),
                      ),
                      InkWell(
                        key: const Key('open_super_app_directory_btn'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => context.push('/super-app-hub'),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 40,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Tất cả',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: c.primary,
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: c.primary,
                                ),
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
          ),
          const SizedBox(height: 6),
          LifeOsResponsiveIconGrid(
            columns: 4,
            children: pinnedSpecs.map((spec) {
              return LifeOsCompactDockItem(
                key: spec.tileKey,
                icon: spec.icon,
                label: spec.label,
                tone: spec.tone,
                onTap: () => context.push(spec.route),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _TodayQuickHubRow extends StatelessWidget {
  const _TodayQuickHubRow();

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LifeOsFeatureBentoTile(
              tileKey: const Key('open_pro_utilities_hub_card'),
              icon: Icons.calculate_outlined,
              tone: LifeOsAccentTone.blue,
              title: 'Công cụ nâng cao',
              subtitle: 'Lãi vay · Tiết kiệm',
              onTap: () => context.push('/pro-utilities'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LifeOsMintHeroCard(
              key: const Key('home_tile_all_services'),
              padding: const EdgeInsets.all(12),
              onTap: () => context.push('/super-app-hub'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const LifeOsIconSquircle(
                        icon: Icons.apps_rounded,
                        tone: LifeOsAccentTone.emerald,
                        solidFill: true,
                        size: 36,
                        iconSize: 18,
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 17,
                        color: c.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tất cả danh mục',
                        softWrap: true,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.2,
                          height: 1.22,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Đầy đủ 20+ tiện ích',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.25,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstActionTipCheck extends StatelessWidget {
  final VoidCallback onDismiss;

  const _FirstActionTipCheck({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final hasZeroMedAndWater = context.select(
      (DailyLifeBloc? b) =>
          b == null ||
          (b.state.snapshot.medications.isEmpty &&
              b.state.snapshot.hydration.waterMl == 0),
    );
    if (!hasZeroMedAndWater) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        key: const Key('today_ftue_first_action_tip'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: c.primarySubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: c.primary.withValues(alpha: 0.24),
            width: 0.85,
          ),
        ),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Bắt đầu trong 10 giây',
              style: TextStyle(
                fontSize: 12.2,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            InkWell(
              key: const Key('today_ftue_quick_action_btn'),
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                BehaviorEventCollector().recordType(
                  BehaviorEventType.quickActionUsed,
                  metadata: const <String, Object?>{
                    'targetId': 'ftue_first_expense',
                    'screenKey': 'today',
                  },
                );
                showLifeOsQuickCreateHub(context);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    'Ghi khoản chi đầu tiên',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: c.primary,
                    ),
                  ),
                ),
              ),
            ),
            InkWell(
              key: const Key('today_ftue_dismiss_tip_btn'),
              borderRadius: BorderRadius.circular(10),
              onTap: onDismiss,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    'Ẩn gợi ý',
                    style: TextStyle(
                      fontSize: 11.8,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
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
}

class _TodayRecommendationsCardSection extends StatelessWidget {
  final PersonalizationSettings personalizationSettings;
  final bool firstActionTipDismissed;
  final VoidCallback onDismissFirstActionTip;
  final VoidCallback onOpenSettings;
  final List<ScoredRecommendation> Function({
    required BehaviorContextSignal signal,
    required List<TransactionEntity> provisionalTxs,
    required List<TaskEntity> openTasks,
    required List<TaskEntity> overdueTasks,
    required int upcomingEventCount,
    required List<VehicleEntity> dueVehicles,
    required List<RecurringBillEntity> dueBills,
    required bool hasConfiguredBudget,
    required int spentPct,
  })
  computeRecommendations;
  final ValueChanged<ScoredRecommendation> onRecommendationTap;
  final ValueChanged<ScoredRecommendation> onRecommendationDismiss;

  const _TodayRecommendationsCardSection({
    required this.personalizationSettings,
    required this.firstActionTipDismissed,
    required this.onDismissFirstActionTip,
    required this.onOpenSettings,
    required this.computeRecommendations,
    required this.onRecommendationTap,
    required this.onRecommendationDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    final monthlyExpenseMinor = context.select(
      (DashboardBloc b) => b.state.data.monthlyExpenseMinor,
    );
    final calEvents = context.select((CalendarBloc b) => b.state.events);
    final allTasks = context.select((TaskBloc b) => b.state.tasks);
    final budgets = context.select((BudgetBloc b) => b.state.budgets);
    final hasActiveFamily = context.select(
      (FamilyBloc b) => b.state.activeFamily != null,
    );
    final allTransactions = context.select(
      (TransactionListBloc b) => b.state.allTransactions,
    );
    final vehicles = context.select((VehicleBloc b) => b.state.vehicles);
    final bills = context.select((VehicleBloc b) => b.state.bills);

    final upcomingEvents = calEvents
        .where((e) => !e.endsAt.isBefore(now))
        .toList();
    final provisionalTxs = allTransactions
        .where(
          (t) =>
              t.verification == TransactionVerification.provisional &&
              !t.isReversed,
        )
        .toList();
    final openTasks = allTasks
        .where((t) => t.status != TaskWorkflowStatus.done)
        .toList();
    final overdueTasks = openTasks
        .where((t) => t.dueAt != null && t.dueAt!.isBefore(startOfToday))
        .toList();
    final dueVehicles = vehicles
        .where((v) => v.dueStateAt(now) != VehicleDueState.healthy)
        .toList();
    final dueBills = bills
        .where((b) => b.nextDueDate.difference(now).inDays <= 7)
        .toList();

    final totalBudgetLimit = budgets.fold<int>(
      0,
      (sum, b) => sum + b.limitMinor,
    );
    final hasConfiguredBudget = totalBudgetLimit > 0;
    final spentPct = hasConfiguredBudget
        ? ((monthlyExpenseMinor * 100) / totalBudgetLimit).clamp(0, 999).round()
        : 0;
    final budgetUsageRatio = hasConfiguredBudget
        ? (monthlyExpenseMinor / totalBudgetLimit).clamp(0.0, 2.0)
        : 0.0;

    final contextSignal = BehaviorContextSignal(
      now: now,
      pendingTaskCount: openTasks.length,
      upcomingEventCount: upcomingEvents.length,
      upcomingBillCount: dueBills.length,
      budgetUsageRatio: budgetUsageRatio,
      hasProvisionalBankTx: provisionalTxs.isNotEmpty,
      hasActiveFamily: hasActiveFamily,
    );

    final contextualRecs = computeRecommendations(
      signal: contextSignal,
      provisionalTxs: provisionalTxs,
      openTasks: openTasks,
      overdueTasks: overdueTasks,
      upcomingEventCount: upcomingEvents.length,
      dueVehicles: dueVehicles,
      dueBills: dueBills,
      hasConfiguredBudget: hasConfiguredBudget,
      spentPct: spentPct,
    );

    final mayShowFirstActionTip =
        allTransactions.isEmpty &&
        calEvents.isEmpty &&
        !firstActionTipDismissed;

    return LifeOsSoftCard(
      key: const Key('today_contextual_recommendation_card'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LifeOsIconSquircle(
                icon: Icons.auto_awesome_outlined,
                tone: LifeOsAccentTone.emerald,
                size: 24,
                iconSize: 13,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gợi ý phù hợp',
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 13.2,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ),
              TextButton(
                key: const Key('today_personalization_settings_btn'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 40),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: onOpenSettings,
                child: const Text('Tùy chỉnh'),
              ),
            ],
          ),
          if (mayShowFirstActionTip)
            _FirstActionTipCheck(onDismiss: onDismissFirstActionTip),
          if (!personalizationSettings.enabled) ...[
            const SizedBox(height: 4),
            Text(
              'Gợi ý thông minh đang tắt. Chạm "Tùy chỉnh" để bật lại bất cứ lúc nào.',
              softWrap: true,
              style: TextStyle(
                fontSize: 11.8,
                height: 1.25,
                color: c.textSecondary,
              ),
            ),
          ] else if (contextualRecs.isEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Mọi gợi ý hiện tại đã gọn gàng. Bạn có thể thay đổi nhóm quan tâm trong "Tùy chỉnh".',
              softWrap: true,
              style: TextStyle(
                fontSize: 11.8,
                height: 1.25,
                color: c.textSecondary,
              ),
            ),
          ] else ...[
            const SizedBox(height: 5),
            _AdaptiveRecommendationTile(
              recommendation: contextualRecs.first,
              onActionTap: () => onRecommendationTap(contextualRecs.first),
              onDismissTap: () => onRecommendationDismiss(contextualRecs.first),
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayMintMetricColumn extends StatelessWidget {
  final int count;
  final String label;
  final Color valueColor;
  final VoidCallback onTap;

  const _TodayMintMetricColumn({
    required this.count,
    required this.label,
    required this.valueColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 20,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.6,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdaptiveRecommendationTile extends StatelessWidget {
  final ScoredRecommendation recommendation;
  final VoidCallback onActionTap;
  final VoidCallback onDismissTap;

  const _AdaptiveRecommendationTile({
    required this.recommendation,
    required this.onActionTap,
    required this.onDismissTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final candidate = recommendation.candidate;
    final (
      IconData icon,
      LifeOsAccentTone tone,
    ) = switch (candidate.interestGroup) {
      UserInterestGroup.spending => (
        Icons.payments_outlined,
        LifeOsAccentTone.emerald,
      ),
      UserInterestGroup.schedule => (
        Icons.event_note_rounded,
        LifeOsAccentTone.blue,
      ),
      UserInterestGroup.family => (
        Icons.groups_2_outlined,
        LifeOsAccentTone.purple,
      ),
      UserInterestGroup.home => (
        Icons.electric_bolt_rounded,
        LifeOsAccentTone.amber,
      ),
      UserInterestGroup.vehicle => (
        Icons.two_wheeler_rounded,
        LifeOsAccentTone.coral,
      ),
      UserInterestGroup.all => (
        Icons.auto_awesome_outlined,
        LifeOsAccentTone.emerald,
      ),
    };

    return Container(
      key: Key('today_rec_card_${candidate.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: c.border.withValues(alpha: 0.72),
          width: 0.85,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = math.max(
            1.0,
            MediaQuery.textScalerOf(context).scale(1.0),
          );
          final useCompactStacked = (constraints.maxWidth / scale) < 250;

          final textColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                candidate.titleVi,
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                candidate.reasonVi,
                softWrap: true,
                style: TextStyle(
                  fontSize: 11.2,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: c.primary,
                ),
              ),
            ],
          );

          final actionBtn = FilledButton.tonal(
            key: Key('today_rec_action_${candidate.id}'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(48, 38),
              padding: const EdgeInsets.symmetric(horizontal: 9),
            ),
            onPressed: onActionTap,
            child: Text(
              candidate.actionLabelVi,
              style: const TextStyle(
                fontSize: 11.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          );

          final dismissBtn = InkWell(
            key: Key('today_rec_dismiss_${candidate.id}'),
            borderRadius: BorderRadius.circular(8),
            onTap: onDismissTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    'Ẩn',
                    style: TextStyle(
                      fontSize: 11.2,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );

          if (useCompactStacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LifeOsIconSquircle(
                      icon: icon,
                      tone: tone,
                      size: 30,
                      iconSize: 15,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: textColumn),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [dismissBtn, actionBtn],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              LifeOsIconSquircle(
                icon: icon,
                tone: tone,
                size: 30,
                iconSize: 15,
              ),
              const SizedBox(width: 8),
              Expanded(child: textColumn),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [actionBtn, dismissBtn],
              ),
            ],
          );
        },
      ),
    );
  }
}
