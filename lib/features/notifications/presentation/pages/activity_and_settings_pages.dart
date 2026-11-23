import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/theme_bloc.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/pages/account_profile_page.dart';
import '../../../calendar/presentation/bloc/calendar_bloc.dart';
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

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final notifState = context.watch<NotificationIngestionBloc>().state;
    final txState = context.watch<TransactionListBloc>().state;
    final calState = context.watch<CalendarBloc>().state;
    final taskState = context.watch<TaskBloc>().state;
    final vehicleState = context.watch<VehicleBloc>().state;
    final timeFmt = DateFormat('dd/MM · HH:mm');

    final seenTxIds = <String>{};
    final items =
        <
          ({
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

    // 1. Real-time Financial Notifications (SePay Webhook, SePay API, Android Listener, Test)
    for (final fn in notifState.financialNotifications.take(30)) {
      if (fn.transactionId.isNotEmpty) {
        seenTxIds.add(fn.transactionId);
      }
      final sign = fn.direction == 'credit' ? '+' : '-';
      final amountText = fn.isTestNotification
          ? '[Thông báo kiểm thử — Không tạo giao dịch thật]'
          : '$sign${VndAmount.format(fn.amountMinor)} · ${fn.bankName} ${fn.accountMasked}';
      items.add((
        category: fn.direction == 'credit' ? 'credit' : 'debit',
        title: fn.title,
        subtitle: '$amountText\n${fn.content}',
        metaBadge: '${fn.statusLabel} · ${fn.sourceLabel}',
        timeLabel: timeFmt.format(fn.occurredAt),
        icon: fn.isTestNotification
            ? Icons.science_outlined
            : (fn.direction == 'credit'
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded),
        tone: fn.isTestNotification
            ? LifeOsAccentTone.blue
            : (fn.direction == 'credit'
                  ? LifeOsAccentTone.emerald
                  : LifeOsAccentTone.coral),
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

    // 2. Remaining Ledger Transactions not yet represented in financialNotifications
    for (final tx in txState.filteredTransactions.take(15)) {
      if (seenTxIds.contains(tx.id)) continue;
      final isCredit = tx.direction == 'credit';
      final srcLabel = switch (tx.sourceKind) {
        _ when tx.sourceKind.name == 'bankWebhook' => 'SePay Webhook',
        _ when tx.sourceKind.name == 'bankApi' => 'SePay API',
        _ when tx.sourceKind.name == 'androidNotification' =>
          'Thông báo Android',
        _ when tx.sourceKind.name == 'csv' => 'Sao kê CSV',
        _ => 'Sổ cái',
      };
      items.add((
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

    // 3. Calendar, Tasks & Vehicle Reminders
    for (final ev in calState.events.take(4)) {
      items.add((
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
    for (final t in taskState.tasks.take(4)) {
      items.add((
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

    final visible = _selectedFilter == 'all'
        ? items
        : items.where((it) => it.category == _selectedFilter).toList();

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
                        // Filter Pills: Tất cả | Tiền vào | Tiền ra | Lịch & Việc
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: filters.map((f) {
                              final active = _selectedFilter == f.$1;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () =>
                                      setState(() => _selectedFilter = f.$1),
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
                                  'Chưa có thông báo biến động nào trong mục này',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Khi tài khoản ngân hàng đã kết nối phát sinh tiền vào/tiền ra qua SePay Webhook hoặc Thông báo Android, giao dịch sẽ hiển thị tức thì tại đây.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12.8,
                                    color: c.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 12),
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

/// Screen 10: "Cài đặt" (`10_Cai_dat.png`) following Unified LifeOS Design System.
class SettingsHubPage extends StatefulWidget {
  const SettingsHubPage({super.key});

  @override
  State<SettingsHubPage> createState() => _SettingsHubPageState();
}

class _SettingsHubPageState extends State<SettingsHubPage> {
  bool _calendarSyncEnabled = true;
  bool _reminderPermissionEnabled = true;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = TammySemanticColors.of(context);
    final notifState = context.watch<NotificationIngestionBloc>().state;
    final bankConsentEnabled = notifState.consent?.enabled ?? false;
    final themeState = context.watch<ThemeBloc>().state;
    final isDark = themeState.themeMode == ThemeMode.dark;

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
                        // 1. Pastel Mint User Profile Card ("Chỉnh sửa hồ sơ")
                        LifeOsMintHeroCard(
                          onTap: () => context.push('/account-profile'),
                          child: Row(
                            children: [
                              UserAvatarBadge(user: user, radius: 28),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.fullName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 18,
                                        height: 1.2,
                                        fontWeight: FontWeight.w800,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      user.email,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: c.separator),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.edit_outlined,
                                      size: 14,
                                      color: c.primary,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Chỉnh sửa hồ sơ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: c.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Nhóm 1: Tài khoản & Kết nối tự động
                        const LifeOsSectionHeader(
                          title: 'Tài khoản & Kết nối tự động',
                          padding: EdgeInsets.only(
                            top: 8,
                            bottom: 6,
                            left: 2,
                            right: 2,
                          ),
                        ),
                        _SettingsCardItem(
                          icon: Icons.person_outline_rounded,
                          tone: LifeOsAccentTone.emerald,
                          title: 'Hồ sơ cá nhân',
                          subtitle: 'Tên hiển thị, email & mật khẩu',
                          onTap: () => context.push('/account-profile'),
                        ),
                        const SizedBox(height: 8),
                        _SettingsCardItem(
                          icon: Icons.calendar_month_rounded,
                          tone: LifeOsAccentTone.blue,
                          title: 'Đồng bộ Google Calendar',
                          subtitle: 'Đồng bộ lịch hẹn & nhắc nhở',
                          statusPillLabel: _calendarSyncEnabled
                              ? 'Đã kết nối'
                              : 'Đang tắt',
                          statusPillTone: _calendarSyncEnabled
                              ? LifeOsAccentTone.emerald
                              : LifeOsAccentTone.neutral,
                          trailing: Switch(
                            value: _calendarSyncEnabled,
                            onChanged: (v) {
                              setState(() => _calendarSyncEnabled = v);
                              if (v) {
                                context.read<CalendarBloc>().add(
                                  GoogleCalendarSyncRequested(
                                    userId: user.id,
                                    userName: user.fullName,
                                    interactive: false,
                                  ),
                                );
                              }
                            },
                          ),
                          onTap: () => context.go('/planning'),
                        ),
                        const SizedBox(height: 8),
                        _SettingsCardItem(
                          icon: Icons.account_balance_outlined,
                          tone: LifeOsAccentTone.emerald,
                          title: 'Nhận diện thông báo ngân hàng',
                          subtitle: 'Tự động ghi nhận biến động số dư',
                          statusPillLabel: bankConsentEnabled
                              ? 'Đang nhận diện'
                              : 'Chưa bật',
                          statusPillTone: bankConsentEnabled
                              ? LifeOsAccentTone.emerald
                              : LifeOsAccentTone.neutral,
                          trailing: Switch(
                            value: bankConsentEnabled,
                            onChanged: (v) {
                              final pkgs =
                                  notifState
                                          .consent
                                          ?.allowedPackages
                                          .isNotEmpty ==
                                      true
                                  ? notifState.consent!.allowedPackages
                                  : kSupportedVnBanks
                                        .map((b) => b.packageName)
                                        .toList();
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
                        const SizedBox(height: 8),
                        _SettingsCardItem(
                          icon: Icons.notifications_none_rounded,
                          tone: LifeOsAccentTone.emerald,
                          title: 'Quyền nhắc nhở',
                          subtitle: 'Chuông báo sự kiện & việc cần làm',
                          statusPillLabel: _reminderPermissionEnabled
                              ? 'Bật nhắc sự kiện'
                              : 'Tạm tắt',
                          statusPillTone: _reminderPermissionEnabled
                              ? LifeOsAccentTone.emerald
                              : LifeOsAccentTone.neutral,
                          trailing: Switch(
                            value: _reminderPermissionEnabled,
                            onChanged: (v) =>
                                setState(() => _reminderPermissionEnabled = v),
                          ),
                          onTap: () => context.push('/event-alarm'),
                        ),

                        // Nhóm 2: Giao diện & Hiển thị
                        const LifeOsSectionHeader(
                          title: 'Giao diện & Hiển thị',
                          tone: LifeOsAccentTone.amber,
                          padding: EdgeInsets.only(
                            top: 12,
                            bottom: 6,
                            left: 2,
                            right: 2,
                          ),
                        ),
                        _SettingsCardItem(
                          icon: Icons.dark_mode_outlined,
                          tone: LifeOsAccentTone.emerald,
                          title: 'Chế độ tối',
                          subtitle: 'Chuyển nhanh giao diện Sáng / Tối',
                          statusPillLabel: isDark ? 'Đang bật' : 'Đang tắt',
                          statusPillTone: isDark
                              ? LifeOsAccentTone.emerald
                              : LifeOsAccentTone.neutral,
                          trailing: Switch(
                            key: const Key('settings_dark_mode_switch'),
                            value: isDark,
                            onChanged: (v) {
                              context.read<ThemeBloc>().add(
                                ThemeModeChanged(
                                  v ? ThemeMode.dark : ThemeMode.light,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        _SettingsCardItem(
                          icon: Icons.text_fields_rounded,
                          tone: LifeOsAccentTone.amber,
                          title: 'Cỡ chữ (Aa) & Bố cục',
                          subtitle: 'Chỉnh cỡ chữ & mật độ hiển thị',
                          statusPillLabel:
                              '${themeState.themeModeLabel} · ${themeState.textScalePercent}%',
                          statusPillTone: LifeOsAccentTone.emerald,
                          onTap: () => showLifeOsAppearanceSheet(context),
                        ),

                        // Nhóm 3: Tiện ích mở rộng & Màn hình chính
                        const LifeOsSectionHeader(
                          title: 'Gia đình & Tiện ích mở rộng',
                          tone: LifeOsAccentTone.purple,
                          padding: EdgeInsets.only(
                            top: 12,
                            bottom: 6,
                            left: 2,
                            right: 2,
                          ),
                        ),
                        _SettingsCardItem(
                          icon: Icons.groups_outlined,
                          tone: LifeOsAccentTone.emerald,
                          title: 'Tài liệu & Quyền chia sẻ gia đình',
                          subtitle: 'Quản lý giấy tờ chung & quyền xem',
                          onTap: () => context.push('/family-documents'),
                        ),
                        const SizedBox(height: 8),
                        _SettingsCardItem(
                          icon: Icons.widgets_outlined,
                          tone: LifeOsAccentTone.purple,
                          title: 'Widget màn hình chính',
                          subtitle: 'Ghim tiện ích ra màn hình điện thoại',
                          onTap: () => context.push('/home-widgets'),
                        ),
                        const SizedBox(height: 8),
                        _SettingsCardItem(
                          icon: Icons.apps_rounded,
                          tone: LifeOsAccentTone.emerald,
                          title: 'Tất cả tiện ích',
                          subtitle: 'Sức khỏe, Đi chợ, Điện nước & Lương',
                          onTap: () => context.push('/super-app-hub'),
                        ),
                        const SizedBox(height: 16),

                        // 9. Bottom Emerald CTA
                        LifeOsPrimaryCtaButton(
                          icon: Icons.link_rounded,
                          trailingIcon: Icons.arrow_forward_rounded,
                          label: 'Quản lý kết nối ngân hàng & quyền riêng tư',
                          onPressed: () =>
                              context.push('/notifications-privacy'),
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

class _SettingsCardItem extends StatelessWidget {
  final IconData icon;
  final LifeOsAccentTone tone;
  final String title;
  final String subtitle;
  final String? statusPillLabel;
  final LifeOsAccentTone statusPillTone;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsCardItem({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    this.statusPillLabel,
    this.statusPillTone = LifeOsAccentTone.emerald,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return LifeOsSoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          LifeOsIconSquircle(icon: icon, tone: tone, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.32,
                    color: c.textSecondary,
                  ),
                ),
                if (statusPillLabel != null) ...[
                  const SizedBox(height: 7),
                  LifeOsStatusPill(
                    icon: statusPillTone == LifeOsAccentTone.emerald
                        ? Icons.check_circle_outline_rounded
                        : null,
                    label: statusPillLabel!,
                    tone: statusPillTone,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing ?? Icon(Icons.chevron_right_rounded, color: c.textSecondary),
        ],
      ),
    );
  }
}
