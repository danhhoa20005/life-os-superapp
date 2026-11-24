import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/theme_bloc.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/services/native_alarm_scheduler_bridge.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vietnamese_search_matcher.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_event.dart';
import '../../../authentication/presentation/pages/account_profile_page.dart';
import '../../../calendar/presentation/bloc/calendar_bloc.dart';
import '../../../financial_ai/presentation/bloc/gemini_copilot_bloc.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../vehicles/presentation/bloc/vehicle_bloc.dart';
import '../bloc/notification_ingestion_bloc.dart';

/// Screen 09: "Thông báo" (Unified Activity & Bank Notification Center).
class ActivityNotificationsPage extends StatefulWidget {
  const ActivityNotificationsPage({super.key});

  @override
  State<ActivityNotificationsPage> createState() =>
      _ActivityNotificationsPageState();
}

class _ActivityNotificationsPageState extends State<ActivityNotificationsPage> {
  String _selectedFilter = 'all';
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _selectedFilter != 'all' || _searchQuery.trim().isNotEmpty;

  void _resetFilters() {
    setState(() {
      _selectedFilter = 'all';
      _searchQuery = '';
      _searchCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final notifState = context.watch<NotificationIngestionBloc>().state;
    final txState = context.watch<TransactionListBloc>().state;
    final calState = context.watch<CalendarBloc>().state;
    final taskState = context.watch<TaskBloc>().state;
    final vehicleState = context.watch<VehicleBloc>().state;
    final timeFmt = DateFormat('dd/MM · HH:mm');
    final now = DateTime.now();

    final seenTxIds = <String>{};
    final items =
        <
          ({
            DateTime sortTime,
            String category, // 'credit' | 'debit' | 'other'
            String title,
            String subtitle,
            String? metaBadge,
            String timeLabel,
            IconData icon,
            LifeOsAccentTone tone,
            VoidCallback onTap,
          })
        >[];

    // 1. Real-time Financial Notifications (excluding internal test items)
    for (final fn
        in notifState.financialNotifications
            .where((f) => !f.isTestNotification)
            .take(30)) {
      if (fn.transactionId.isNotEmpty) {
        seenTxIds.add(fn.transactionId);
      }
      final sign = fn.direction == 'credit' ? '+' : '-';
      final amountText =
          '$sign${VndAmount.format(fn.amountMinor)} · ${fn.bankName} ${fn.accountMasked}';
      items.add((
        sortTime: fn.occurredAt,
        category: fn.direction == 'credit' ? 'credit' : 'debit',
        title: fn.title,
        subtitle: '$amountText\n${fn.content}',
        metaBadge: '${fn.statusLabel} · ${fn.sourceLabel}',
        timeLabel: timeFmt.format(fn.occurredAt),
        icon: fn.direction == 'credit'
            ? Icons.south_west_rounded
            : Icons.north_east_rounded,
        tone: fn.direction == 'credit'
            ? LifeOsAccentTone.emerald
            : LifeOsAccentTone.coral,
        onTap: () {
          if (fn.transactionId.isNotEmpty) {
            context.push(
              '/auto-tx-review?txId=${Uri.encodeQueryComponent(fn.transactionId)}',
            );
          } else {
            context.push('/notifications-privacy');
          }
        },
      ));
    }

    // 2. Remaining Transactions not yet represented in financialNotifications
    for (final tx in txState.allTransactions.take(20)) {
      if (seenTxIds.contains(tx.id)) continue;
      final isCredit = tx.direction == 'credit';
      final srcLabel = switch (tx.sourceKind) {
        _ when tx.sourceKind.name == 'bankWebhook' => 'Đồng bộ tự động',
        _ when tx.sourceKind.name == 'bankApi' => 'Đối soát ngân hàng',
        _ when tx.sourceKind.name == 'androidNotification' =>
          'Thông báo điện thoại',
        _ when tx.sourceKind.name == 'csv' => 'Sao kê ngân hàng',
        _ => 'Ghi thủ công',
      };
      items.add((
        sortTime: tx.occurredAt,
        category: isCredit ? 'credit' : 'debit',
        title: isCredit ? 'Tiền vào sổ quỹ' : 'Giao dịch chi tiêu',
        subtitle:
            '${isCredit ? "+" : "-"}${VndAmount.format(tx.amountMinor)} · ${tx.merchant}',
        metaBadge:
            '${tx.isConfirmedInLedger ? "Đã xác nhận" : "Chờ đối soát"} · $srcLabel',
        timeLabel: timeFmt.format(tx.occurredAt),
        icon: Icons.account_balance_wallet_outlined,
        tone: isCredit ? LifeOsAccentTone.emerald : LifeOsAccentTone.coral,
        onTap: () => context.push('/auto-tx-review', extra: tx),
      ));
    }

    // 3. Upcoming Calendar, Open Tasks & Vehicle Reminders
    for (final ev in calState.events
        .where((e) => !e.endsAt.isBefore(now.subtract(const Duration(days: 1))))
        .take(6)) {
      items.add((
        sortTime: ev.startsAt,
        category: 'other',
        title: 'Sự kiện lịch: ${ev.title}',
        subtitle: ev.location ?? 'Lịch hẹn đã đồng bộ',
        metaBadge: 'Lịch trình',
        timeLabel: timeFmt.format(ev.startsAt),
        icon: Icons.calendar_today_rounded,
        tone: LifeOsAccentTone.blue,
        onTap: () => context.push('/event-detail', extra: ev),
      ));
    }
    for (final t in taskState.tasks
        .where(
          (t) =>
              t.status.name != 'done' &&
              t.status.name != 'declined',
        )
        .take(6)) {
      items.add((
        sortTime: t.dueAt ?? now,
        category: 'other',
        title: 'Công việc: ${t.title}',
        subtitle: 'Giao cho ${t.assigneeName}',
        metaBadge: 'Việc cần làm',
        timeLabel: t.dueAt != null ? timeFmt.format(t.dueAt!) : 'Hôm nay',
        icon: Icons.task_alt_rounded,
        tone: LifeOsAccentTone.amber,
        onTap: () => context.push('/tasks-board'),
      ));
    }
    for (final v in vehicleState.vehicles.take(2)) {
      items.add((
        sortTime: now.subtract(const Duration(hours: 2)),
        category: 'other',
        title: 'Bảo dưỡng xe ${v.name}',
        subtitle: 'Còn ${v.remainingKm} km đến mốc bảo dưỡng định kỳ',
        metaBadge: 'Phương tiện',
        timeLabel: 'Định kỳ',
        icon: Icons.directions_car_outlined,
        tone: LifeOsAccentTone.emerald,
        onTap: () => context.push('/assets'),
      ));
    }

    items.sort((a, b) => b.sortTime.compareTo(a.sortTime));

    final q = _searchQuery.trim();
    final visible = items.where((it) {
      if (_selectedFilter != 'all' && it.category != _selectedFilter) {
        return false;
      }
      if (q.isNotEmpty) {
        return VietnameseSearchMatcher.matchesAny(q, [
          it.title,
          it.subtitle,
          it.metaBadge,
        ]);
      }
      return true;
    }).toList();

    final filters = const <(String key, String label)>[
      ('all', 'Tất cả'),
      ('credit', 'Tiền vào'),
      ('debit', 'Tiền ra'),
      ('other', 'Lịch & Việc'),
    ];

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              LifeOsTopBrandHeader(
                title: 'Thông báo & Biến động',
                showBackButton: true,
                showUnreadNotificationDot: false,
                trailingAction: TextButton.icon(
                  onPressed: () => context.push('/notifications-privacy'),
                  icon: const Icon(Icons.tune_rounded, size: 17),
                  label: const Text('Cài đặt'),
                ),
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
                        TextField(
                          key: const Key('activity_search_field'),
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Tìm biến động, lịch hẹn, việc làm...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 19),
                            suffixIcon: _searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    key: const Key('activity_search_clear_btn'),
                                    tooltip: 'Xóa tìm kiếm',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => setState(() {
                                      _searchCtrl.clear();
                                      _searchQuery = '';
                                    }),
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Filter Pills: Tất cả | Tiền vào | Tiền ra | Lịch & Việc
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: filters.map((f) {
                              final active = f.$1 == 'all'
                                  ? !_hasActiveFilters
                                  : _selectedFilter == f.$1;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    if (f.$1 == 'all') {
                                      _resetFilters();
                                    } else {
                                      setState(() {
                                        _selectedFilter =
                                            _selectedFilter == f.$1
                                            ? 'all'
                                            : f.$1;
                                      });
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: active ? c.primary : c.surface,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: active ? c.primary : c.separator,
                                      ),
                                    ),
                                    child: Text(
                                      f.$2,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: active
                                            ? Colors.white
                                            : c.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (visible.isEmpty)
                          LifeOsMintHeroCard(
                            child: Column(
                              children: [
                                const LifeOsIconSquircle(
                                  icon: Icons.notifications_none_rounded,
                                  tone: LifeOsAccentTone.emerald,
                                  size: 52,
                                  iconSize: 26,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _hasActiveFilters
                                      ? 'Không có thông báo khớp bộ lọc'
                                      : 'Chưa có thông báo biến động nào',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _hasActiveFilters
                                      ? 'Bấm "Xem tất cả thông báo" để bỏ bộ lọc hiện tại.'
                                      : 'Khi tài khoản ngân hàng đã kết nối phát sinh tiền vào/tiền ra hoặc có lịch hẹn mới, thông báo sẽ hiển thị tức thì tại đây.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12.8,
                                    color: c.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (_hasActiveFilters)
                                  FilledButton.tonalIcon(
                                    key: const Key('activity_reset_filter_btn'),
                                    onPressed: _resetFilters,
                                    icon: const Icon(
                                      Icons.filter_alt_off_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('Xem tất cả thông báo'),
                                  )
                                else
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        context.push('/notifications-privacy'),
                                    icon: const Icon(
                                      Icons.account_balance_rounded,
                                      size: 17,
                                    ),
                                    label: const Text(
                                      'Mở Ngân hàng & Đồng bộ giao dịch',
                                    ),
                                  ),
                              ],
                            ),
                          )
                        else
                          ...visible.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: LifeOsSoftCard(
                                onTap: item.onTap,
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LifeOsIconSquircle(
                                      icon: item.icon,
                                      tone: item.tone,
                                      size: 42,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.title,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 14.5,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                item.timeLabel,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: c.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            item.subtitle,
                                            style: TextStyle(
                                              fontSize: 12.8,
                                              height: 1.35,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                          if (item.metaBadge != null) ...[
                                            const SizedBox(height: 6),
                                            LifeOsStatusPill(
                                              label: item.metaBadge!,
                                              tone: item.tone,
                                            ),
                                          ],
                                        ],
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen 10: Redesigned "Cài đặt" following Apple Settings / Revolut Grouped Pro Max Architecture.
class SettingsHubPage extends StatefulWidget {
  const SettingsHubPage({super.key});

  @override
  State<SettingsHubPage> createState() => _SettingsHubPageState();
}

class _SettingsItemSpec {
  final Key? itemKey;
  final String sectionTitle;
  final LifeOsAccentTone sectionTone;
  final IconData icon;
  final LifeOsAccentTone tone;
  final String title;
  final String subtitle;
  final String keywords;
  final String? statusPillLabel;
  final LifeOsAccentTone statusPillTone;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsItemSpec({
    this.itemKey,
    required this.sectionTitle,
    this.sectionTone = LifeOsAccentTone.emerald,
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    this.keywords = '',
    this.statusPillLabel,
    this.statusPillTone = LifeOsAccentTone.emerald,
    this.trailing,
    this.onTap,
  });
}

class _SettingsHubPageState extends State<SettingsHubPage>
    with WidgetsBindingObserver {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  BackgroundReminderReadiness _bgReadiness =
      BackgroundReminderReadiness.allReady;
  bool _hasAppPin = false;
  bool _hideBalances = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshSystemAndSecurityStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSystemAndSecurityStatus();
    }
  }

  Future<void> _refreshSystemAndSecurityStatus() async {
    final readiness = await NativeAlarmSchedulerBridge.instance
        .getBackgroundReadiness();
    final hasPin = await UserBehaviorPrefs.hasAppPinCode();
    final hideBal = await UserBehaviorPrefs.loadHideBalances();
    if (!mounted) return;
    setState(() {
      _bgReadiness = readiness;
      _hasAppPin = hasPin;
      _hideBalances = hideBal;
    });
  }

  Future<void> _confirmAndSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất tài khoản?'),
        content: const Text(
          'Phiên đăng nhập trên thiết bị này sẽ đóng lại. Dữ liệu đám mây của bạn vẫn được bảo toàn an toàn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('confirm_settings_sign_out_btn'),
            style: FilledButton.styleFrom(
              backgroundColor: TammySemanticColors.of(ctx).error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AuthBloc>().add(const AuthSignOutRequested());
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = TammySemanticColors.of(context);
    final notifState = context.watch<NotificationIngestionBloc>().state;
    final bankConsentEnabled = notifState.consent?.enabled ?? false;
    final calState = context.watch<CalendarBloc>().state;
    final calendarSyncEnabled = calState.isGoogleAuthorized;
    final themeState = context.watch<ThemeBloc>().state;
    final isDark = themeState.themeMode == ThemeMode.dark;

    var geminiReady = false;
    try {
      geminiReady = context
          .watch<GeminiCopilotBloc>()
          .state
          .config
          .isReadyForCloud;
    } catch (_) {}

    final securityCount = <bool>[
      user.emailVerified,
      user.hasPasswordProvider,
      user.isGoogleLinked,
      _hasAppPin,
    ].where((v) => v).length;

    final allItems = <_SettingsItemSpec>[
      // Nhóm 1: Tài khoản, Kết nối & Chạy ngầm
      _SettingsItemSpec(
        itemKey: const Key('settings_account_security_row'),
        sectionTitle: 'Tài khoản & Kết nối tự động',
        sectionTone: LifeOsAccentTone.emerald,
        icon: Icons.shield_outlined,
        tone: LifeOsAccentTone.emerald,
        title: 'Hồ sơ & Bảo mật tài khoản',
        subtitle: 'Mật khẩu, mã PIN, múi giờ & thiết bị',
        keywords: 'ho so bao mat mat khau ma pin email mui gio',
        statusPillLabel: 'An toàn $securityCount/4',
        statusPillTone: securityCount >= 3
            ? LifeOsAccentTone.emerald
            : LifeOsAccentTone.amber,
        onTap: () => context
            .push('/account-profile')
            .then((_) => _refreshSystemAndSecurityStatus()),
      ),
      _SettingsItemSpec(
        sectionTitle: 'Tài khoản & Kết nối tự động',
        sectionTone: LifeOsAccentTone.emerald,
        icon: Icons.calendar_month_rounded,
        tone: LifeOsAccentTone.blue,
        title: 'Đồng bộ Google Calendar',
        subtitle: 'Đồng bộ lịch hẹn & nhắc nhở hai chiều',
        keywords: 'dong bo google calendar lich hen',
        statusPillLabel: calendarSyncEnabled ? 'Đã kết nối' : 'Chưa nối',
        statusPillTone: calendarSyncEnabled
            ? LifeOsAccentTone.emerald
            : LifeOsAccentTone.neutral,
        trailing: Switch(
          value: calendarSyncEnabled,
          onChanged: (v) {
            if (v) {
              context.read<CalendarBloc>().add(
                GoogleCalendarSyncRequested(
                  userId: user.id,
                  userName: user.fullName,
                  interactive: true,
                ),
              );
            } else {
              context.go('/planning');
            }
          },
        ),
        onTap: () => context.go('/planning'),
      ),
      _SettingsItemSpec(
        sectionTitle: 'Tài khoản & Kết nối tự động',
        sectionTone: LifeOsAccentTone.emerald,
        icon: Icons.account_balance_outlined,
        tone: LifeOsAccentTone.emerald,
        title: 'Nhận diện thông báo ngân hàng',
        subtitle: 'Tự động ghi nhận biến động số dư',
        keywords: 'nhan dien thong bao ngan hang bien dong so du vietqr',
        statusPillLabel: bankConsentEnabled ? 'Đang nhận diện' : 'Chưa bật',
        statusPillTone: bankConsentEnabled
            ? LifeOsAccentTone.emerald
            : LifeOsAccentTone.neutral,
        trailing: Switch(
          value: bankConsentEnabled,
          onChanged: (v) {
            final pkgs =
                notifState.consent?.allowedPackages.isNotEmpty == true
                ? notifState.consent!.allowedPackages
                : kSupportedVnBanks.map((b) => b.packageName).toList();
            context.read<NotificationIngestionBloc>().add(
              ConsentConfigUpdated(
                userId: user.id,
                enabled: v,
                allowedPackages: pkgs,
                autoConfirmSignals: v,
              ),
            );
          },
        ),
        onTap: () => context.push('/notifications-privacy'),
      ),

      // Nhóm 2: Giao diện, Cỡ chữ & Quyền riêng tư
      _SettingsItemSpec(
        sectionTitle: 'Giao diện & Quyền riêng tư',
        sectionTone: LifeOsAccentTone.amber,
        icon: Icons.dark_mode_outlined,
        tone: LifeOsAccentTone.emerald,
        title: 'Chế độ tối',
        subtitle: 'Chuyển nhanh giao diện Sáng / Tối dịu mắt',
        keywords: 'che do toi sang giao dien dark mode',
        statusPillLabel: isDark ? 'Đang bật' : 'Đang tắt',
        statusPillTone: isDark
            ? LifeOsAccentTone.emerald
            : LifeOsAccentTone.neutral,
        trailing: Switch(
          key: const Key('settings_dark_mode_switch'),
          value: isDark,
          onChanged: (v) {
            context.read<ThemeBloc>().add(
              ThemeModeChanged(v ? ThemeMode.dark : ThemeMode.light),
            );
          },
        ),
      ),
      _SettingsItemSpec(
        itemKey: const Key('settings_appearance_row'),
        sectionTitle: 'Giao diện & Quyền riêng tư',
        sectionTone: LifeOsAccentTone.amber,
        icon: Icons.text_fields_rounded,
        tone: LifeOsAccentTone.amber,
        title: 'Cỡ chữ (Aa) & Bố cục',
        subtitle: 'Chỉnh tỷ lệ chữ & mật độ hiển thị',
        keywords: 'co chu aa bo cuc phong to thu nho',
        statusPillLabel:
            '${themeState.themeModeLabel} · ${themeState.textScalePercent}%',
        statusPillTone: LifeOsAccentTone.emerald,
        onTap: () => showLifeOsAppearanceSheet(context),
      ),
      _SettingsItemSpec(
        sectionTitle: 'Giao diện & Quyền riêng tư',
        sectionTone: LifeOsAccentTone.amber,
        icon: Icons.visibility_off_outlined,
        tone: LifeOsAccentTone.purple,
        title: 'Ẩn số dư nhạy cảm',
        subtitle: 'Che số tiền trên Trang chủ khi mở ứng dụng',
        keywords: 'an so du nhay cam che tien rieng tu',
        statusPillLabel: _hideBalances ? 'Đang che số' : 'Hiển thị số',
        statusPillTone: _hideBalances
            ? LifeOsAccentTone.emerald
            : LifeOsAccentTone.neutral,
        trailing: Switch(
          key: const Key('settings_hide_balances_switch'),
          value: _hideBalances,
          onChanged: (val) async {
            setState(() => _hideBalances = val);
            await UserBehaviorPrefs.saveHideBalances(val);
          },
        ),
      ),
      _SettingsItemSpec(
        sectionTitle: 'Giao diện & Quyền riêng tư',
        sectionTone: LifeOsAccentTone.amber,
        icon: Icons.event_available_outlined,
        tone: LifeOsAccentTone.blue,
        title: 'Chia sẻ khung giờ rảnh/bận',
        subtitle: 'Cho phép thành viên nhóm xem giờ trống lịch',
        keywords: 'chia se khung gio ranh ban lich gia dinh',
        statusPillLabel: user.availabilityOptIn ? 'Đang chia sẻ' : 'Riêng tư',
        statusPillTone: user.availabilityOptIn
            ? LifeOsAccentTone.emerald
            : LifeOsAccentTone.neutral,
        trailing: Switch(
          key: const Key('settings_availability_switch'),
          value: user.availabilityOptIn,
          onChanged: (val) =>
              context.read<AuthBloc>().add(AuthAvailabilitySharingToggled(val)),
        ),
      ),

      // Nhóm 3: Thông báo chạy ngầm & Trợ lý thông minh
      _SettingsItemSpec(
        itemKey: const Key('settings_bg_notif_row'),
        sectionTitle: 'Thông báo ngầm & Trợ lý thông minh',
        sectionTone: LifeOsAccentTone.blue,
        icon: Icons.phonelink_ring_rounded,
        tone: LifeOsAccentTone.blue,
        title: 'Thông báo ngoài màn hình & Chạy ngầm',
        subtitle: 'Nhắc uống nước, thuốc trên màn hình khóa',
        keywords: 'thong bao ngoai man hinh chay ngam quyen nhac nho pin',
        statusPillLabel: _bgReadiness.isFullyOptimized
            ? 'Sẵn sàng chạy ngầm'
            : 'Cần cấp quyền',
        statusPillTone: _bgReadiness.isFullyOptimized
            ? LifeOsAccentTone.emerald
            : LifeOsAccentTone.amber,
        onTap: () => context
            .push('/health-hub?tab=water')
            .then((_) => _refreshSystemAndSecurityStatus()),
      ),
      _SettingsItemSpec(
        itemKey: const Key('settings_financial_ai_card'),
        sectionTitle: 'Thông báo ngầm & Trợ lý thông minh',
        sectionTone: LifeOsAccentTone.blue,
        icon: Icons.bolt_rounded,
        tone: LifeOsAccentTone.emerald,
        title: 'Trợ lý thông minh & Kết nối Gemini',
        subtitle: 'Xử lý tiếng Việt trên máy & liên kết đám mây',
        keywords: 'tro ly thong minh gemini nhap nhanh',
        statusPillLabel: geminiReady ? 'Đã nối Gemini' : '100% trên máy',
        statusPillTone: LifeOsAccentTone.emerald,
        onTap: () => context.push('/financial-ai-settings'),
      ),

      // Nhóm 4: Gia đình, Tiện ích & Hệ thống
      _SettingsItemSpec(
        sectionTitle: 'Gia đình & Tiện ích mở rộng',
        sectionTone: LifeOsAccentTone.purple,
        icon: Icons.alarm_on_rounded,
        tone: LifeOsAccentTone.coral,
        title: 'Báo thức & Chuông nhắc lịch',
        subtitle: 'Quản lý chuông báo thức cá nhân chuẩn giờ',
        keywords: 'bao thuc chuong nhac lich hen gio',
        onTap: () => context.push('/event-alarm'),
      ),
      _SettingsItemSpec(
        sectionTitle: 'Gia đình & Tiện ích mở rộng',
        sectionTone: LifeOsAccentTone.purple,
        icon: Icons.groups_outlined,
        tone: LifeOsAccentTone.emerald,
        title: 'Tài liệu & Quyền chia sẻ gia đình',
        subtitle: 'Quản lý giấy tờ chung & quyền xem',
        keywords: 'tai lieu giay to quyen chia se gia dinh can cuoc',
        onTap: () => context.push('/family-documents'),
      ),
      _SettingsItemSpec(
        sectionTitle: 'Gia đình & Tiện ích mở rộng',
        sectionTone: LifeOsAccentTone.purple,
        icon: Icons.widgets_outlined,
        tone: LifeOsAccentTone.purple,
        title: 'Widget màn hình chính',
        subtitle: 'Ghim tiện ích ra màn hình điện thoại',
        keywords: 'widget man hinh chinh ghim thu am',
        onTap: () => context.push('/home-widgets'),
      ),
      _SettingsItemSpec(
        sectionTitle: 'Gia đình & Tiện ích mở rộng',
        sectionTone: LifeOsAccentTone.purple,
        icon: Icons.apps_rounded,
        tone: LifeOsAccentTone.emerald,
        title: 'Tất cả tiện ích',
        subtitle: 'Sức khỏe, Đi chợ, Điện nước & Lương',
        keywords: 'tat ca tien ich 360 suc khoe di cho dien nuoc luong',
        onTap: () => context.push('/super-app-hub'),
      ),
      _SettingsItemSpec(
        itemKey: const Key('settings_brand_kit_row'),
        sectionTitle: 'Gia đình & Tiện ích mở rộng',
        sectionTone: LifeOsAccentTone.purple,
        icon: Icons.palette_outlined,
        tone: LifeOsAccentTone.emerald,
        title: 'Nhận diện thương hiệu LifeOS',
        subtitle: 'Biểu tượng & bảng màu chuẩn hệ thống',
        keywords: 'nhan dien thuong hieu logo bang mau',
        onTap: () => showLifeOsBrandIdentitySheet(context),
      ),
    ];

    final q = _query.trim();
    final filtered = q.isEmpty
        ? allItems
        : allItems.where((it) {
            return VietnameseSearchMatcher.matchesAny(q, [
              it.title,
              it.subtitle,
              it.keywords,
              it.sectionTitle,
              it.statusPillLabel,
            ]);
          }).toList();

    final grouped =
        <
          String,
          ({LifeOsAccentTone tone, List<_SettingsItemSpec> items})
        >{};
    for (final it in filtered) {
      final bucket = grouped.putIfAbsent(
        it.sectionTitle,
        () => (tone: it.sectionTone, items: <_SettingsItemSpec>[]),
      );
      bucket.items.add(it);
    }

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              const LifeOsTopBrandHeader(
                title: 'Cài đặt',
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
                        // 1. Instant Vietnamese Settings Search Bar
                        TextField(
                          key: const Key('settings_search_input'),
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Tìm mục cài đặt',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 19,
                            ),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    key: const Key('settings_search_clear_btn'),
                                    tooltip: 'Xóa tìm kiếm',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => setState(() {
                                      _searchCtrl.clear();
                                      _query = '';
                                    }),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 2. Identity & Security Summary Hero Card
                        if (q.isEmpty) ...[
                          LifeOsMintHeroCard(
                            key: const Key('settings_hero_profile_card'),
                            onTap: () => context
                                .push('/account-profile')
                                .then((_) => _refreshSystemAndSecurityStatus()),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    UserAvatarBadge(user: user, radius: 25),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user.fullName,
                                            softWrap: true,
                                            style: TextStyle(
                                              fontSize: 17,
                                              height: 1.2,
                                              fontWeight: FontWeight.w800,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              user.email,
                                              style: TextStyle(
                                                fontSize: 12.6,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: c.textSecondary,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    LifeOsStatusPill(
                                      icon: Icons.verified_user_outlined,
                                      label: 'Bảo mật $securityCount/4 lớp',
                                      tone: securityCount >= 3
                                          ? LifeOsAccentTone.emerald
                                          : LifeOsAccentTone.amber,
                                    ),
                                    LifeOsStatusPill(
                                      icon: _hasAppPin
                                          ? Icons.pin_rounded
                                          : Icons.dialpad_rounded,
                                      label: _hasAppPin
                                          ? 'Mã PIN: Đã bật'
                                          : 'Mã PIN: Chưa bật',
                                      tone: _hasAppPin
                                          ? LifeOsAccentTone.emerald
                                          : LifeOsAccentTone.neutral,
                                    ),
                                    const LifeOsStatusPill(
                                      icon: Icons.edit_outlined,
                                      label: 'Chỉnh sửa hồ sơ',
                                      tone: LifeOsAccentTone.emerald,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // 3. Empty Search Fallback
                        if (grouped.isEmpty)
                          LifeOsSoftCard(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 38,
                                  color: c.textSecondary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Không tìm thấy mục cài đặt',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Thử từ khóa khác hoặc bấm nút bên dưới để xem toàn bộ danh mục.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: c.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  key: const Key('settings_search_reset_btn'),
                                  onPressed: () => setState(() {
                                    _searchCtrl.clear();
                                    _query = '';
                                  }),
                                  icon: const Icon(
                                    Icons.filter_alt_off_rounded,
                                    size: 17,
                                  ),
                                  label: const Text('Xem tất cả cài đặt'),
                                ),
                              ],
                            ),
                          ),

                        // 4. Grouped Apple/Revolut Settings Sections
                        for (final entry in grouped.entries) ...[
                          LifeOsSectionHeader(
                            title: entry.key,
                            tone: entry.value.tone,
                            padding: const EdgeInsets.only(
                              top: 10,
                              bottom: 6,
                              left: 2,
                              right: 2,
                            ),
                          ),
                          LifeOsSoftCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (
                                  var i = 0;
                                  i < entry.value.items.length;
                                  i++
                                ) ...[
                                  if (i > 0)
                                    Divider(
                                      height: 1,
                                      thickness: 0.7,
                                      indent: 62,
                                      endIndent: 14,
                                      color: c.separator,
                                    ),
                                  _SettingsGroupedRow(
                                    spec: entry.value.items[i],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],

                        if (q.isEmpty) ...[
                          const SizedBox(height: 16),
                          LifeOsPrimaryCtaButton(
                            icon: Icons.link_rounded,
                            trailingIcon: Icons.arrow_forward_rounded,
                            label:
                                'Quản lý kết nối ngân hàng & quyền riêng tư',
                            onPressed: () =>
                                context.push('/notifications-privacy'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            key: const Key('settings_sign_out_button'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: c.error,
                              side: BorderSide(
                                color: c.error.withValues(alpha: 0.42),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => _confirmAndSignOut(context),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Đăng xuất khỏi thiết bị này'),
                          ),
                        ],
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

class _SettingsGroupedRow extends StatelessWidget {
  final _SettingsItemSpec spec;

  const _SettingsGroupedRow({required this.spec});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Material(
      key: spec.itemKey,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: spec.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              LifeOsIconSquircle(
                icon: spec.icon,
                tone: spec.tone,
                size: 38,
                iconSize: 19,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.title,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14.2,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      spec.subtitle,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.28,
                        color: c.textSecondary,
                      ),
                    ),
                    if (spec.statusPillLabel != null) ...[
                      const SizedBox(height: 5),
                      LifeOsStatusPill(
                        icon: spec.statusPillTone == LifeOsAccentTone.emerald
                            ? Icons.check_circle_outline_rounded
                            : null,
                        label: spec.statusPillLabel!,
                        tone: spec.statusPillTone,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              spec.trailing ??
                  Icon(Icons.chevron_right_rounded, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
