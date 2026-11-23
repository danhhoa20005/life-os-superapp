import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/voice_smart_capture_sheet.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../pro_utilities/presentation/bloc/pro_utilities_bloc.dart';
import '../bloc/daily_life_bloc.dart';

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
  const SuperAppDirectoryPage({super.key});

  @override
  State<SuperAppDirectoryPage> createState() => _SuperAppDirectoryPageState();
}

class _SuperAppDirectoryPageState extends State<SuperAppDirectoryPage> {
  String _query = '';
  String _domainFilter = 'all';

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
      route: '/wealth-tools',
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: 'Tài chính · Ngân hàng · Thuế Lương',
      shortLabel: 'Lương Gross–Net',
      keywords: 'thuế tncn bhxh bảo hiểm lương thực nhận',
      icon: Icons.request_quote_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/smart-notes-hub',
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

    // 2. SỨC KHỎE, BẾP GIA ĐÌNH & KỶ LUẬT SỐNG
    SuperAppServiceEntry(
      domainKey: 'health_food',
      domainTitle: 'Sức khỏe · Bếp & Đi chợ · Kỷ luật',
      shortLabel: 'Sức khỏe & SOS',
      keywords: 'tủ thuốc uống thuốc bmi huyết áp bhyt 115',
      icon: Icons.favorite_outline_rounded,
      tone: LifeOsAccentTone.coral,
      route: '/health-hub',
    ),
    SuperAppServiceEntry(
      domainKey: 'health_food',
      domainTitle: 'Sức khỏe · Bếp & Đi chợ · Kỷ luật',
      shortLabel: 'Bếp & Đi chợ',
      keywords: 'hôm nay ăn gì thực đơn giỏ chợ tủ lạnh',
      icon: Icons.shopping_basket_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/kitchen-groceries',
    ),
    SuperAppServiceEntry(
      domainKey: 'health_food',
      domainTitle: 'Sức khỏe · Bếp & Đi chợ · Kỷ luật',
      shortLabel: 'Tập trung & Nước',
      keywords: 'thói quen tập trung uống nước 2000ml pomodoro',
      icon: Icons.local_fire_department_outlined,
      tone: LifeOsAccentTone.amber,
      route: '/habits-focus',
    ),
    SuperAppServiceEntry(
      domainKey: 'health_food',
      domainTitle: 'Sức khỏe · Bếp & Đi chợ · Kỷ luật',
      shortLabel: 'Sổ tay & Cảm xúc',
      keywords: 'sổ tay ghim nhật ký cảm xúc tâm trạng mood',
      icon: Icons.sticky_note_2_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/smart-notes-hub',
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
  ];

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final dash = context.watch<DashboardBloc>().state.data;
    final dailySnap = context.watch<DailyLifeBloc>().state.snapshot;
    final proSnap = context.watch<ProUtilitiesBloc>().state;

    final q = _query.trim().toLowerCase();
    final filtered = _catalog.where((e) {
      if (_domainFilter != 'all' && e.domainKey != _domainFilter) return false;
      if (q.isEmpty) return true;
      return e.shortLabel.toLowerCase().contains(q) ||
          e.keywords.toLowerCase().contains(q) ||
          e.domainTitle.toLowerCase().contains(q);
    }).toList();

    final grouped = <String, List<SuperAppServiceEntry>>{};
    for (final item in filtered) {
      grouped.putIfAbsent(item.domainTitle, () => []).add(item);
    }

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
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
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        2,
                        AppSpacing.md,
                        AppSpacing.xl,
                      ),
                      children: [
                        // Compact Live Pulse Bar
                        LifeOsMintHeroCard(
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
                                label:
                                    'Ví: ${VndAmount.format(dash.netWorthMinor)}',
                                tone: LifeOsAccentTone.emerald,
                              ),
                              LifeOsStatusPill(
                                icon: Icons.medication_outlined,
                                label: 'Thuốc: ${dailySnap.medications.length}',
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
                        const SizedBox(height: 10),

                        // Compact Instant Search
                        TextField(
                          key: const Key('super_app_directory_search_input'),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText:
                                'Tìm nhanh: điện EVN, đi chợ, thuốc, lương, lãi vay...',
                            prefixIcon: Icon(Icons.search_rounded, size: 20),
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
                                    selected: _domainFilter == f.$1,
                                    onSelected: (_) =>
                                        setState(() => _domainFilter = f.$1),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

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
