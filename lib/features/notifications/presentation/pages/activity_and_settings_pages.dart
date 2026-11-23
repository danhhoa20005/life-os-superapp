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
  State<ActivityNotificationsPage> createState() => _ActivityNotificationsPageState();
}

class _ActivityNotificationsPageState extends State<ActivityNotificationsPage> {
  String _selectedFilter = 'all';
  bool _reminderEnabled = true;

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final txState = context.watch<TransactionListBloc>().state;
    final calState = context.watch<CalendarBloc>().state;
    final taskState = context.watch<TaskBloc>().state;
    final vehicleState = context.watch<VehicleBloc>().state;
    final timeFmt = DateFormat('HH:mm');

    final items = <({
      String category,
      String title,
      String subtitle,
      String timeLabel,
      IconData icon,
      LifeOsAccentTone tone,
      VoidCallback onTap,
    })>[
      for (final tx in txState.filteredTransactions.take(5))
        (
          category: 'bank',
          title: 'Giao dịch sổ quỹ mới',
          subtitle:
              '${tx.direction == "credit" ? "+" : "-"}${VndAmount.format(tx.amountMinor)} · ${tx.merchant}',
          timeLabel: timeFmt.format(tx.occurredAt),
          icon: Icons.account_balance_wallet_outlined,
          tone: tx.direction == 'credit'
              ? LifeOsAccentTone.emerald
              : LifeOsAccentTone.coral,
          onTap: () => context.push('/auto-tx-review', extra: tx),
        ),
      for (final ev in calState.events.take(4))
        (
          category: 'calendar',
          title: 'Sắp đến sự kiện lịch',
          subtitle: '${ev.title} (${timeFmt.format(ev.startsAt)})',
          timeLabel: timeFmt.format(ev.startsAt),
          icon: Icons.calendar_today_rounded,
          tone: LifeOsAccentTone.blue,
          onTap: () => context.push('/event-detail', extra: ev),
        ),
      for (final t in taskState.tasks.take(4))
        (
          category: 'task',
          title: 'Công việc gia đình',
          subtitle: '${t.title} · Giao cho ${t.assigneeName}',
          timeLabel: t.dueAt != null ? timeFmt.format(t.dueAt!) : 'Hôm nay',
          icon: Icons.task_alt_rounded,
          tone: LifeOsAccentTone.amber,
          onTap: () => context.push('/tasks-board'),
        ),
      for (final v in vehicleState.vehicles.take(2))
        (
          category: 'task',
          title: 'Bảo dưỡng xe ${v.name}',
          subtitle: 'Còn ${v.remainingKm} km đến mốc bảo dưỡng định kỳ',
          timeLabel: 'Định kỳ',
          icon: Icons.directions_car_outlined,
          tone: LifeOsAccentTone.emerald,
          onTap: () => context.go('/assets'),
        ),
    ];

    // Provide realistic starter preview items if user's feed is brand-new
    if (items.isEmpty) {
      items.addAll([
        (
          category: 'bank',
          title: 'Giao dịch ngân hàng (Tự động)',
          subtitle: 'Nhận diện biến động số dư tự động qua SePay & Thông báo Android',
          timeLabel: 'Mới đây',
          icon: Icons.account_balance_rounded,
          tone: LifeOsAccentTone.emerald,
          onTap: () => context.push('/auto-tx-review'),
        ),
        (
          category: 'calendar',
          title: 'Nhắc hẹn & Báo thức sự kiện',
          subtitle: 'Nhấn để xem thử màn hình Báo thức sự kiện 07:30 toàn màn hình',
          timeLabel: '07:30',
          icon: Icons.alarm_on_rounded,
          tone: LifeOsAccentTone.blue,
          onTap: () => context.push('/event-alarm'),
        ),
      ]);
    }

    final visible = _selectedFilter == 'all'
        ? items
        : items.where((it) => it.category == _selectedFilter).toList();

    final filters = const <(String key, String label)>[
      ('all', 'Tất cả'),
      ('bank', 'Ngân hàng'),
      ('calendar', 'Lịch'),
      ('task', 'Công việc'),
    ];

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              LifeOsTopBrandHeader(
                title: 'Thông báo',
                showBackButton: true,
                showUnreadNotificationDot: false,
                trailingAction: Switch.adaptive(
                  value: _reminderEnabled,
                  onChanged: (v) => setState(() => _reminderEnabled = v),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        4,
                        AppSpacing.md,
                        AppSpacing.xxl,
                      ),
                      children: [
                        // Filter Pills: Tất cả | Ngân hàng | Lịch | Công việc
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: filters.map((f) {
                              final active = _selectedFilter == f.$1;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => setState(() => _selectedFilter = f.$1),
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
                                        color: active ? Colors.white : c.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 14),
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
                                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                        const SizedBox(height: 3),
                                        Text(
                                          item.subtitle,
                                          style: TextStyle(
                                            fontSize: 12.8,
                                            color: c.textSecondary,
                                          ),
                                        ),
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
                    constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
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
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      user.email,
                                      maxLines: 1,
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
                                    Icon(Icons.edit_outlined, size: 14, color: c.primary),
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

                        // 2. Hồ sơ cá nhân
                        _SettingsCardItem(
                          icon: Icons.person_outline_rounded,
                          tone: LifeOsAccentTone.emerald,
                          title: 'Hồ sơ cá nhân',
                          subtitle: 'Tên hiển thị, email & mật khẩu',
                          onTap: () => context.push('/account-profile'),
                        ),
                        const SizedBox(height: 10),

                        // 3. Đồng bộ Google Calendar
                        _SettingsCardItem(
                          icon: Icons.calendar_month_rounded,
                          tone: LifeOsAccentTone.blue,
                          title: 'Đồng bộ Google Calendar',
                          subtitle: 'Đồng bộ lịch hẹn & nhắc nhở',
                          statusPillLabel: _calendarSyncEnabled ? 'Đã kết nối' : 'Đang tắt',
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
                        const SizedBox(height: 10),

                        // 4. Nhận diện thông báo ngân hàng
                        _SettingsCardItem(
                          icon: Icons.account_balance_outlined,
                          tone: LifeOsAccentTone.emerald,
                          title: 'Nhận diện thông báo ngân hàng',
                          subtitle: 'Tự động ghi nhận biến động số dư',
                          statusPillLabel: bankConsentEnabled ? 'Đang nhận diện' : 'Chưa bật',
                          statusPillTone: bankConsentEnabled
                              ? LifeOsAccentTone.emerald
                              : LifeOsAccentTone.neutral,
                          trailing: Switch(
                            value: bankConsentEnabled,
                            onChanged: (v) {
                              final pkgs = notifState.consent?.allowedPackages.isNotEmpty == true
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
                        const SizedBox(height: 10),

                        // 5. Quyền nhắc nhở
                        _SettingsCardItem(
                          icon: Icons.notifications_none_rounded,
                          tone: LifeOsAccentTone.emerald,
                          title: 'Quyền nhắc nhở',
                          subtitle: 'Chuông báo sự kiện & việc cần làm',
                          statusPillLabel:
                              _reminderPermissionEnabled ? 'Bật nhắc sự kiện' : 'Tạm tắt',
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
                        const SizedBox(height: 10),

                        // 6. Chế độ tối
                        _SettingsCardItem(
                          icon: Icons.dark_mode_outlined,
                          tone: LifeOsAccentTone.emerald,
                          title: 'Chế độ tối',
                          subtitle: 'Chuyển nhanh giao diện Sáng / Tối',
                          statusPillLabel: isDark ? 'Đang bật' : 'Đang tắt',
                          statusPillTone:
                              isDark ? LifeOsAccentTone.emerald : LifeOsAccentTone.neutral,
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
                        const SizedBox(height: 10),

                        // 6b. Tùy chỉnh Giao diện & Cỡ chữ (Aa)
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
                        const SizedBox(height: 10),

                        // 7. Tài liệu & Quyền riêng tư gia đình
                        _SettingsCardItem(
                          icon: Icons.groups_outlined,
                          tone: LifeOsAccentTone.emerald,
                          title: 'Tài liệu & Quyền chia sẻ gia đình',
                          subtitle: 'Quản lý giấy tờ chung & quyền xem',
                          onTap: () => context.push('/family-documents'),
                        ),
                        const SizedBox(height: 10),

                        // 8. Widget Màn hình chính
                        _SettingsCardItem(
                          icon: Icons.widgets_outlined,
                          tone: LifeOsAccentTone.purple,
                          title: 'Widget màn hình chính',
                          subtitle: 'Ghim tiện ích ra màn hình điện thoại',
                          onTap: () => context.push('/home-widgets'),
                        ),
                        const SizedBox(height: 10),

                        // 8b. Tất cả tiện ích
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
                          onPressed: () => context.push('/notifications-privacy'),
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
