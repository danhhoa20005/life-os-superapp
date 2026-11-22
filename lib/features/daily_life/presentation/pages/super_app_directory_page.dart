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
  final String title;
  final String subtitle;
  final IconData icon;
  final LifeOsAccentTone tone;
  final String route;
  final bool isShellTab;

  const SuperAppServiceEntry({
    required this.domainKey,
    required this.domainTitle,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tone,
    required this.route,
    this.isShellTab = false,
  });
}

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
      domainTitle: '1. Tài chính · Ngân hàng · Thuế Lương',
      title: 'Sổ cái Ví & Ngân sách',
      subtitle: 'Theo dõi đa ví, hạn mức danh mục & phân tích thu chi',
      icon: Icons.account_balance_wallet_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/finance',
      isShellTab: true,
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: '1. Tài chính · Ngân hàng · Thuế Lương',
      title: 'Tự động bắt giao dịch SePay',
      subtitle: 'Đối soát biến động số dư tự động 98% độ tin cậy',
      icon: Icons.auto_awesome_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/auto-tx-review',
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: '1. Tài chính · Ngân hàng · Thuế Lương',
      title: 'Quét Bill AI · Lãi Vay · FIRE',
      subtitle: 'Bóc tách hóa đơn siêu thị, dư nợ giảm dần & 6 Chiếc Lọ',
      icon: Icons.calculate_outlined,
      tone: LifeOsAccentTone.blue,
      route: '/wealth-tools',
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: '1. Tài chính · Ngân hàng · Thuế Lương',
      title: 'Lương Gross ⇄ Net & Thuế TNCN',
      subtitle: 'Tính BHXH 10.5%, giảm trừ gia cảnh & 7 bậc thuế Việt Nam',
      icon: Icons.request_quote_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/smart-notes-hub',
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: '1. Tài chính · Ngân hàng · Thuế Lương',
      title: 'Báo cáo tuần W1–W4 & Xuất CSV',
      subtitle: 'Xu hướng chi tiêu gia đình và sao kê minh bạch',
      icon: Icons.bar_chart_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/finance-report',
    ),
    SuperAppServiceEntry(
      domainKey: 'finance',
      domainTitle: '1. Tài chính · Ngân hàng · Thuế Lương',
      title: 'Radar Gói đăng ký & Bảo hành',
      subtitle: 'Chặn phí trừ ngầm hằng tháng & canh hạn bảo hành điện máy',
      icon: Icons.radar_rounded,
      tone: LifeOsAccentTone.amber,
      route: '/subscriptions-warranty',
    ),

    // 2. SỨC KHỎE, BẾP GIA ĐÌNH & ĐI CHỢ
    SuperAppServiceEntry(
      domainKey: 'health_food',
      domainTitle: '2. Sức khỏe · Y tế · Bếp & Đi chợ',
      title: 'Sức khỏe, Tủ thuốc & SOS 115',
      subtitle: 'Nhắc uống thuốc đúng cữ, BMI Châu Á, huyết áp & thẻ BHYT',
      icon: Icons.favorite_outline_rounded,
      tone: LifeOsAccentTone.coral,
      route: '/health-hub',
    ),
    SuperAppServiceEntry(
      domainKey: 'health_food',
      domainTitle: '2. Sức khỏe · Y tế · Bếp & Đi chợ',
      title: 'Bếp Gia đình & Đi chợ Thông minh',
      subtitle: 'Gợi ý "Hôm nay ăn gì?", giỏ chợ 1 chạm trừ Ví & tủ lạnh',
      icon: Icons.shopping_basket_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/kitchen-groceries',
    ),
    SuperAppServiceEntry(
      domainKey: 'health_food',
      domainTitle: '2. Sức khỏe · Y tế · Bếp & Đi chợ',
      title: 'Nước uống 2L · Thói quen · Pomodoro',
      subtitle: 'Đồng hồ tập trung sâu 25p/45p & chuỗi kỷ luật mỗi ngày',
      icon: Icons.local_fire_department_outlined,
      tone: LifeOsAccentTone.amber,
      route: '/habits-focus',
    ),

    // 3. NHÀ CỬA, ĐIỆN NƯỚC EVN, XE CỘ & TÀI LIỆU
    SuperAppServiceEntry(
      domainKey: 'home_assets',
      domainTitle: '3. Nhà cửa · Điện nước EVN · Xe cộ & Giấy tờ',
      title: 'Điện 6 bậc EVN · Nước · Phòng trọ',
      subtitle: 'Tính công tơ điện bậc thang +8% VAT, chia phòng & hợp đồng thuê',
      icon: Icons.electric_bolt_rounded,
      tone: LifeOsAccentTone.amber,
      route: '/home-living',
    ),
    SuperAppServiceEntry(
      domainKey: 'home_assets',
      domainTitle: '3. Nhà cửa · Điện nước EVN · Xe cộ & Giấy tờ',
      title: 'Xe cộ · Bảo dưỡng · Đăng kiểm',
      subtitle: 'Theo dõi Odometer, thay dầu định kỳ & hạn bảo hiểm xe',
      icon: Icons.directions_car_outlined,
      tone: LifeOsAccentTone.blue,
      route: '/assets',
      isShellTab: true,
    ),
    SuperAppServiceEntry(
      domainKey: 'home_assets',
      domainTitle: '3. Nhà cửa · Điện nước EVN · Xe cộ & Giấy tờ',
      title: 'Kho Tài liệu & Giấy tờ Gia đình',
      subtitle: 'Lưu hợp đồng, căn cước, bảo hiểm & hóa đơn quan trọng',
      icon: Icons.folder_open_rounded,
      tone: LifeOsAccentTone.purple,
      route: '/family-documents',
    ),

    // 4. LỊCH TRÌNH, TỔ ẤM, XÃ HỘI & TIỆN ÍCH AI
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: '4. Lịch trình · Tổ ấm · Hiếu hỷ & Giọng nói AI',
      title: 'Lịch trình & Google Calendar 2 chiều',
      subtitle: 'Lịch Ngày/Tuần/Tháng & đồng bộ trực tiếp Google Calendar',
      icon: Icons.calendar_today_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/planning',
      isShellTab: true,
    ),
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: '4. Lịch trình · Tổ ấm · Hiếu hỷ & Giọng nói AI',
      title: 'Báo thức Sự kiện Toàn màn hình',
      subtitle: 'Chuông báo sự kiện quan trọng kèm nút Hoãn 5 phút',
      icon: Icons.alarm_on_rounded,
      tone: LifeOsAccentTone.blue,
      route: '/event-alarm',
    ),
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: '4. Lịch trình · Tổ ấm · Hiếu hỷ & Giọng nói AI',
      title: 'Bảng Kanban Việc nhà & Phân công',
      subtitle: 'Giao việc theo thành viên và theo dõi tiến độ trực quan',
      icon: Icons.task_alt_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/tasks-board',
    ),
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: '4. Lịch trình · Tổ ấm · Hiếu hỷ & Giọng nói AI',
      title: 'Không gian Tổ ấm & Chia tiền Nhóm',
      subtitle: 'Quản lý thành viên, mã mời gia đình & cấn trừ công nợ',
      icon: Icons.groups_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/family',
      isShellTab: true,
    ),
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: '4. Lịch trình · Tổ ấm · Hiếu hỷ & Giọng nói AI',
      title: 'Quỹ chung Gia đình & Mục tiêu lớn',
      subtitle: 'Quỹ du lịch, quỹ khẩn cấp & lịch sử đóng góp từng người',
      icon: Icons.savings_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/family-funds',
    ),
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: '4. Lịch trình · Tổ ấm · Hiếu hỷ & Giọng nói AI',
      title: 'Sổ Hiếu Hỷ "Có Đi Có Lại" & Hành lý',
      subtitle: 'Tra cứu mừng cưới/tân gia 2 chiều & checklist đồ du lịch',
      icon: Icons.card_giftcard_rounded,
      tone: LifeOsAccentTone.purple,
      route: '/social-ledger-travel',
    ),
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: '4. Lịch trình · Tổ ấm · Hiếu hỷ & Giọng nói AI',
      title: 'Sổ tay Ghi chú Ghim & Nhật ký Cảm xúc',
      subtitle: 'Ghim ghi chú quan trọng, mật khẩu Wi-Fi & check-in tâm trạng',
      icon: Icons.sticky_note_2_outlined,
      tone: LifeOsAccentTone.amber,
      route: '/smart-notes-hub',
    ),
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: '4. Lịch trình · Tổ ấm · Hiếu hỷ & Giọng nói AI',
      title: '4 Widget Màn hình chính & Giọng nói AI',
      subtitle: 'Ghim 4 widget Android ngoài màn hình chính & nói câu chia tiền',
      icon: Icons.widgets_outlined,
      tone: LifeOsAccentTone.blue,
      route: '/home-widgets',
    ),
    SuperAppServiceEntry(
      domainKey: 'family_life',
      domainTitle: '4. Lịch trình · Tổ ấm · Hiếu hỷ & Giọng nói AI',
      title: 'Cài đặt · Giao diện Tối · Cập nhật OTA',
      subtitle: 'Hồ sơ bảo mật, True Dark Mode & kiểm tra bản mới tự động',
      icon: Icons.settings_outlined,
      tone: LifeOsAccentTone.neutral,
      route: '/settings-hub',
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
      return e.title.toLowerCase().contains(q) ||
          e.subtitle.toLowerCase().contains(q) ||
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
                subtitle: 'Hệ sinh thái Siêu ứng dụng quản lý trọn vẹn mọi mặt đời sống.',
                showBackButton: true,
                trailingAction: IconButton.filled(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Trợ lý Giọng nói AI',
                  onPressed: () =>
                      showVoiceSmartCaptureSheet(context, autoStartListening: true),
                  icon: const Icon(Icons.mic_rounded, size: 18),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        4,
                        AppSpacing.md,
                        AppSpacing.xxl,
                      ),
                      children: [
                        // Super App 360° Live Pulse Hero Card
                        LifeOsMintHeroCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const LifeOsIconSquircle(
                                    icon: Icons.apps_rounded,
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
                                          'Trung tâm Điều hành Cuộc sống 360°',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          '${_catalog.length} phân hệ chuyên sâu · Đồng bộ Cloud thời gian thực · 0₫ phí ẩn',
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
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  LifeOsStatusPill(
                                    icon: Icons.account_balance_wallet_outlined,
                                    label: 'Tài sản: ${VndAmount.format(dash.netWorthMinor)}',
                                    tone: LifeOsAccentTone.emerald,
                                  ),
                                  LifeOsStatusPill(
                                    icon: Icons.medication_outlined,
                                    label: 'Tủ thuốc: ${dailySnap.medications.length}',
                                    tone: LifeOsAccentTone.coral,
                                  ),
                                  LifeOsStatusPill(
                                    icon: Icons.shopping_cart_outlined,
                                    label: 'Giỏ chợ: ${dailySnap.pendingGroceriesCount} món',
                                    tone: LifeOsAccentTone.blue,
                                  ),
                                  LifeOsStatusPill(
                                    icon: Icons.radar_rounded,
                                    label:
                                        'Gói đăng ký: ${proSnap.subscriptionsAndWarranties.length}',
                                    tone: LifeOsAccentTone.purple,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Instant Super App Search Bar
                        TextField(
                          key: const Key('super_app_directory_search_input'),
                          decoration: const InputDecoration(
                            hintText:
                                'Tìm tiện ích: điện EVN, đi chợ, thuốc, lương, lãi vay, lịch...',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                        const SizedBox(height: 10),

                        // Domain Filter Pills
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final f in const [
                                ('all', 'Tất cả dịch vụ'),
                                ('finance', 'Tài chính & Lương'),
                                ('health_food', 'Sức khỏe & Đi chợ'),
                                ('home_assets', 'Điện nước & Nhà xe'),
                                ('family_life', 'Lịch · Tổ ấm · AI'),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
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
                        const SizedBox(height: 12),

                        for (final entry in grouped.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 8),
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          ...entry.value.map(
                            (svc) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: LifeOsSoftCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                onTap: () {
                                  if (svc.isShellTab) {
                                    context.go(svc.route);
                                  } else {
                                    context.push(svc.route);
                                  }
                                },
                                child: Row(
                                  children: [
                                    LifeOsIconSquircle(
                                      icon: svc.icon,
                                      tone: svc.tone,
                                      size: 42,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            svc.title,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14.2,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                          Text(
                                            svc.subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: c.textSecondary,
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
