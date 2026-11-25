import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vietnamese_search_matcher.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/voice_smart_capture_sheet.dart';
import '../../../authentication/domain/entities/user_entity.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../pro_utilities/presentation/bloc/pro_utilities_bloc.dart';
import '../bloc/daily_life_bloc.dart';

UserEntity? _maybeReadAuthUser(BuildContext context) {
  try {
    return BlocProvider.of<AuthBloc>(context, listen: true).state.user;
  } catch (_) {
    return null;
  }
}

class SuperAppServiceEntry {
  final String domainKey;
  final String domainTitle;
  final String shortLabel;
  final String keywords;
  final IconData icon;
  final LifeOsAccentTone tone;
  final String route;
  final bool isShellTab;

  const SuperAppServiceEntry({
    required this.domainKey,
    required this.domainTitle,
    required this.shortLabel,
    required this.keywords,
    required this.icon,
    required this.tone,
    required this.route,
    this.isShellTab = false,
  });
}

/// Space-optimized 4-column Super App Directory (MoMo / Grab / ZaloPay style)
/// organizing all 21+ LifeOS services into clean, scannable category cards.
class SuperAppDirectoryPage extends StatefulWidget {
  final bool isEmbeddedShellTab;

  const SuperAppDirectoryPage({
    super.key,
    this.isEmbeddedShellTab = false,
  });

  @override
  State<SuperAppDirectoryPage> createState() => _SuperAppDirectoryPageState();
}

class _SuperAppDirectoryPageState extends State<SuperAppDirectoryPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String _domainFilter = 'all';
  bool _hideBalances = false;

  @override
  void initState() {
    super.initState();
    UserBehaviorPrefs.loadHideBalances().then((hide) {
      if (mounted && hide != _hideBalances) {
        setState(() => _hideBalances = hide);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _resetDirectoryFilters() {
    setState(() {
      _searchCtrl.clear();
      _query = '';
      _domainFilter = 'all';
    });
  }

  static const List<SuperAppServiceEntry> _catalog = [
    // 1. TÀI CHÍNH, NGÂN HÀNG & THUẾ LƯƠNG
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: 'Tài chính · Ngân hàng · Thuế Lương',
      shortLabel: 'Sổ thu chi',
      keywords: 'chi tiêu ngân sách ví tiền sổ cái',
      icon: Icons.account_balance_wallet_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/finance',
      isShellTab: true,
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: 'Tài chính · Ngân hàng · Thuế Lương',
      shortLabel: 'Ngân hàng & QR',
      keywords: 'ngân hàng tự động biến động số dư mã qr thu tiền',
      icon: Icons.qr_code_2_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/notifications-privacy',
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: 'Tài chính · Ngân hàng · Thuế Lương',
      shortLabel: 'Tách hóa đơn',
      keywords: 'quét hóa đơn lãi vay tự do tài chính 6 chiếc lọ bill ai fire',
      icon: Icons.calculate_outlined,
      tone: LifeOsAccentTone.blue,
      route: '/wealth-tools?tab=receipt',
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: 'Tài chính · Ngân hàng · Thuế Lương',
      shortLabel: 'Lương Gross–Net',
      keywords: 'thuế tncn bhxh bảo hiểm lương thực nhận',
      icon: Icons.request_quote_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/smart-notes-hub?tab=salary',
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: 'Tài chính · Ngân hàng · Thuế Lương',
      shortLabel: 'Báo cáo thu chi',
      keywords: 'thống kê biểu đồ xuất csv w1 w4',
      icon: Icons.bar_chart_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/finance-report',
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: 'Tài chính · Ngân hàng · Thuế Lương',
      shortLabel: 'Thuê bao & BH',
      keywords: 'netflix youtube bảo hành điện máy gói đăng ký',
      icon: Icons.radar_rounded,
      tone: LifeOsAccentTone.amber,
      route: '/subscriptions-warranty',
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: 'Tài chính · Ngân hàng · Thuế Lương',
      shortLabel: 'Quỹ chung',
      keywords: 'tiết kiệm mục tiêu gia đình',
      icon: Icons.savings_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/family-funds',
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: 'Tài chính · Ngân hàng · Thuế Lương',
      shortLabel: 'Sổ Hiếu Hỷ',
      keywords: 'mừng cưới tân gia lễ tết hành lý',
      icon: Icons.card_giftcard_rounded,
      tone: LifeOsAccentTone.purple,
      route: '/social-ledger-travel',
    ),

    // 2. SỨC KHỎE, BẾP GIA ĐÌNH & ĐỜI SỐNG
    SuperAppServiceEntry(
      domainKey: 'health_food',
      domainTitle: 'Sức khỏe · Bếp & Đời sống',
      shortLabel: 'Sức khỏe & SOS',
      keywords: 'tủ thuốc uống thuốc bmi huyết áp bhyt 115',
      icon: Icons.favorite_outline_rounded,
      tone: LifeOsAccentTone.coral,
      route: '/health-hub',
    ),
    SuperAppServiceEntry(
      domainKey: 'health_food',
      domainTitle: 'Sức khỏe · Bếp & Đời sống',
      shortLabel: 'Bếp & Đi chợ',
      keywords: 'hôm nay ăn gì thực đơn giỏ chợ tủ lạnh',
      icon: Icons.shopping_basket_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/kitchen-groceries',
    ),
    SuperAppServiceEntry(
      domainKey: 'health_food',
      domainTitle: 'Sức khỏe · Bếp & Đời sống',
      shortLabel: 'Đồng hồ & Nước',
      keywords: 'thói quen tập trung uống nước 2000ml pomodoro',
      icon: Icons.local_fire_department_outlined,
      tone: LifeOsAccentTone.amber,
      route: '/habits-focus',
    ),
    SuperAppServiceEntry(
      domainKey: 'health_food',
      domainTitle: 'Sức khỏe · Bếp & Đời sống',
      shortLabel: 'Ghi chú nhanh',
      keywords: 'sổ tay ghi chú ghim mã số checklist',
      icon: Icons.sticky_note_2_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/smart-notes-hub?tab=notes',
    ),

    // 3. NHÀ CỬA, ĐIỆN NƯỚC EVN, XE CỘ & GIẤY TỜ
    SuperAppServiceEntry(
      domainKey: 'home_assets',
      domainTitle: 'Nhà cửa · Điện EVN · Xe cộ & Giấy tờ',
      shortLabel: 'Điện nước EVN',
      keywords: '5 bậc thang công tơ phòng trọ hợp đồng thuê nhà',
      icon: Icons.electric_bolt_rounded,
      tone: LifeOsAccentTone.amber,
      route: '/home-living',
    ),
    SuperAppServiceEntry(
      domainKey: 'home_assets',
      domainTitle: 'Nhà cửa · Điện EVN · Xe cộ & Giấy tờ',
      shortLabel: 'Xe & Bảo dưỡng',
      keywords: 'odometer thay dầu đăng kiểm bảo hiểm xe',
      icon: Icons.directions_car_outlined,
      tone: LifeOsAccentTone.blue,
      route: '/assets',
    ),
    SuperAppServiceEntry(
      domainKey: 'home_assets',
      domainTitle: 'Nhà cửa · Điện EVN · Xe cộ & Giấy tờ',
      shortLabel: 'Kho Tài liệu',
      keywords: 'hợp đồng căn cước giấy tờ bảo hiểm',
      icon: Icons.folder_open_rounded,
      tone: LifeOsAccentTone.purple,
      route: '/family-documents',
    ),
    SuperAppServiceEntry(
      domainKey: 'home_assets',
      domainTitle: 'Nhà cửa · Điện EVN · Xe cộ & Giấy tờ',
      shortLabel: '4 Widget Chính',
      keywords: 'ghim màn hình chính giọng nói chia tiền',
      icon: Icons.widgets_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/home-widgets',
    ),

    // 4. LỊCH TRÌNH, VIỆC LÀM & GIA ĐÌNH
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: 'Lịch trình · Việc nhà · Tổ ấm & Hệ thống',
      shortLabel: 'Lịch Google',
      keywords: 'lịch ngày tuần tháng google calendar',
      icon: Icons.calendar_today_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/planning',
      isShellTab: true,
    ),
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: 'Lịch trình · Việc nhà · Tổ ấm & Hệ thống',
      shortLabel: 'Báo thức Lịch',
      keywords: 'chuông nhắc hẹn hoãn 5 phút',
      icon: Icons.alarm_on_rounded,
      tone: LifeOsAccentTone.blue,
      route: '/event-alarm',
    ),
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: 'Lịch trình · Việc nhà · Tổ ấm & Hệ thống',
      shortLabel: 'Việc cần làm',
      keywords: 'phân công việc nhà tiến độ kanban',
      icon: Icons.task_alt_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/tasks-board',
    ),
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: 'Lịch trình · Việc nhà · Tổ ấm & Hệ thống',
      shortLabel: 'Tổ ấm & Nhóm',
      keywords: 'thành viên chia tiền nhóm ở ghép',
      icon: Icons.groups_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/family',
      isShellTab: true,
    ),
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: 'Lịch trình · Việc nhà · Tổ ấm & Hệ thống',
      shortLabel: 'Motion Studio',
      keywords:
          'motion studio gallery hieu ung chuyen dong lo xo shader lottie',
      icon: Icons.auto_awesome_motion_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/motion-gallery',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final dash = context.watch<DashboardBloc>().state.data;
    final dailySnap = context.watch<DailyLifeBloc>().state.snapshot;
    final proSnap = context.watch<ProUtilitiesBloc>().state;

    final q = _query.trim();
    final hasActiveFilters = _domainFilter != 'all' || q.isNotEmpty;
    final filtered = _catalog.where((e) {
      if (_domainFilter != 'all' && e.domainKey != _domainFilter) return false;
      // Hide developer / diagnostic showcase (`Motion Studio`) from everyday browsing
      // unless explicitly searched by keyword!
      if (q.isEmpty && e.route == '/motion-gallery') return false;
      if (q.isEmpty) return true;
      return VietnameseSearchMatcher.matchesAny(q, [
        e.shortLabel,
        e.keywords,
        e.domainTitle,
        if (e.route == '/health-hub') 'uống nước nhắc nước nhắc thuốc',
      ]);
    }).toList();

    final grouped = <String, List<SuperAppServiceEntry>>{};
    for (final item in filtered) {
      grouped.putIfAbsent(item.domainTitle, () => []).add(item);
    }

    final authUser = widget.isEmbeddedShellTab
        ? _maybeReadAuthUser(context)
        : null;

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              if (widget.isEmbeddedShellTab)
                const LifeOsTopBrandHeader(title: 'Menu')
              else
                LifeOsTopBrandHeader(
                  title: 'Tất cả Dịch vụ 360°',
                  showBackButton: true,
                  trailingAction: IconButton.filled(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Ghi bằng giọng nói',
                    onPressed: () => showVoiceSmartCaptureSheet(
                      context,
                      autoStartListening: true,
                    ),
                    icon: const Icon(Icons.mic_rounded, size: 18),
                  ),
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.maxContentWidth,
                    ),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        2,
                        AppSpacing.md,
                        widget.isEmbeddedShellTab ? 96 : AppSpacing.xl,
                      ),
                      children: [
                        if (widget.isEmbeddedShellTab) ...[
                          _FacebookMenuProfileCard(user: authUser),
                          const SizedBox(height: 10),
                        ],

                        // Compact Instant Search
                        TextField(
                          key: const Key('super_app_directory_search_input'),
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Tìm dịch vụ, tiện ích',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 20,
                            ),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    key: const Key(
                                      'super_app_directory_clear_btn',
                                    ),
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
                          onChanged: (v) => setState(() => _query = v),
                        ),
                        const SizedBox(height: 8),

                        // Compact Category Filter Chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final f in const [
                                ('all', 'Tất cả'),
                                ('finance', 'Tài chính & Lương'),
                                ('health_food', 'Sức khỏe & Bếp'),
                                ('home_assets', 'Điện EVN & Nhà xe'),
                                ('family_life', 'Lịch & Gia đình'),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(f.$2),
                                    selected: f.$1 == 'all'
                                        ? !hasActiveFilters
                                        : _domainFilter == f.$1,
                                    onSelected: (_) {
                                      if (f.$1 == 'all') {
                                        _resetDirectoryFilters();
                                      } else {
                                        setState(() {
                                          _domainFilter =
                                              _domainFilter == f.$1
                                              ? 'all'
                                              : f.$1;
                                        });
                                      }
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Progressive Disclosure Live Stats Section
                        LifeOsDetailsDiscloseSection(
                          toggleKey: const Key(
                            'directory_stats_details_toggle',
                          ),
                          label: 'Chi tiết số liệu',
                          contentPadding: const EdgeInsets.only(top: 8),
                          child: LifeOsMintHeroCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                LifeOsStatusPill(
                                  icon: Icons.account_balance_wallet_outlined,
                                  label: _hideBalances
                                      ? 'Ví: •••••• ₫'
                                      : 'Ví: ${VndAmount.format(dash.netWorthMinor)}',
                                  tone: LifeOsAccentTone.emerald,
                                ),
                                LifeOsStatusPill(
                                  icon: Icons.medication_outlined,
                                  label:
                                      'Thuốc: ${dailySnap.medications.length}',
                                  tone: LifeOsAccentTone.coral,
                                ),
                                LifeOsStatusPill(
                                  icon: Icons.shopping_cart_outlined,
                                  label:
                                      'Chợ: ${dailySnap.pendingGroceriesCount}',
                                  tone: LifeOsAccentTone.blue,
                                ),
                                LifeOsStatusPill(
                                  icon: Icons.radar_rounded,
                                  label:
                                      'Thuê bao: ${proSnap.subscriptionsAndWarranties.length}',
                                  tone: LifeOsAccentTone.purple,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (grouped.isEmpty)
                          LifeOsSoftCard(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 38,
                                  color: c.textSecondary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Không tìm thấy dịch vụ phù hợp',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  key: const Key(
                                    'super_app_directory_reset_btn',
                                  ),
                                  onPressed: _resetDirectoryFilters,
                                  icon: const Icon(
                                    Icons.filter_alt_off_rounded,
                                    size: 17,
                                  ),
                                  label: const Text('Xem tất cả dịch vụ'),
                                ),
                              ],
                            ),
                          ),

                        // Grouped 4-Column Super App Icon Cards (Zero vertical bloat & zero truncation!)
                        for (final entry in grouped.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: LifeOsSoftCard(
                              padding: const EdgeInsets.fromLTRB(
                                10,
                                12,
                                10,
                                10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Text(
                                      entry.key,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  LifeOsResponsiveIconGrid(
                                    columns: 4,
                                    children: entry.value.map((svc) {
                                      return LifeOsCompactDockItem(
                                        icon: svc.icon,
                                        label: svc.shortLabel,
                                        tone: svc.tone,
                                        onTap: () {
                                          if (svc.isShellTab) {
                                            context.go(svc.route);
                                          } else {
                                            context.push(svc.route);
                                          }
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
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

class _FacebookMenuProfileCard extends StatelessWidget {
  final UserEntity? user;

  const _FacebookMenuProfileCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final rawName = user?.fullName.trim() ?? '';
    final displayName = rawName.isEmpty ? 'Người dùng LifeOS' : rawName;
    final initials = user?.initials ?? 'L';
    final photoUrl = user?.photoUrl;

    return LifeOsSoftCard(
      key: const Key('menu_tab_profile_card'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('menu_tab_profile_header_row'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push('/account-profile'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [c.primary, c.secondary],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.72),
                          width: 1.5,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Xem hồ sơ cá nhân & bảo mật',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: c.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MenuQuickActionPill(
                pillKey: const Key('menu_tab_appearance_chip'),
                icon: Icons.palette_outlined,
                label: 'Giao diện & Cỡ chữ',
                tone: LifeOsAccentTone.purple,
                onTap: () => showLifeOsAppearanceSheet(context),
              ),
              _MenuQuickActionPill(
                pillKey: const Key('menu_tab_settings_chip'),
                icon: Icons.settings_outlined,
                label: 'Cài đặt',
                tone: LifeOsAccentTone.blue,
                onTap: () => context.push('/settings-hub'),
              ),
              _MenuQuickActionPill(
                pillKey: const Key('menu_tab_voice_chip'),
                icon: Icons.mic_rounded,
                label: 'Ghi giọng nói',
                tone: LifeOsAccentTone.emerald,
                onTap: () => showVoiceSmartCaptureSheet(
                  context,
                  autoStartListening: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuQuickActionPill extends StatelessWidget {
  final Key? pillKey;
  final IconData icon;
  final String label;
  final LifeOsAccentTone tone;
  final VoidCallback onTap;

  const _MenuQuickActionPill({
    this.pillKey,
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final (bg, fg) = tone.resolve(context);

    return Material(
      color: bg,
      shape: StadiumBorder(
        side: BorderSide(color: fg.withValues(alpha: 0.24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: pillKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LifeOsIconSquircle(
                icon: icon,
                tone: tone,
                size: 22,
                iconSize: 13,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: c.textPrimary,
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
