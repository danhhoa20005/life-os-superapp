import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/lifeos_brand_colors.dart';
import '../../features/authentication/presentation/bloc/auth_bloc.dart';
import '../../features/daily_life/domain/entities/daily_life_entities.dart';
import '../../features/daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../features/dashboard/domain/entities/dashboard_entities.dart';
import '../../features/dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../features/family/presentation/bloc/family_bloc.dart';
import '../../features/tasks/domain/entities/task_entities.dart';
import '../../features/tasks/presentation/bloc/task_bloc.dart';
import '../../features/vehicles/presentation/bloc/vehicle_bloc.dart';
import '../utils/vietnamese_search_matcher.dart';
import '../utils/vnd_amount.dart';
import 'lifeos_design_system.dart';
import 'voice_smart_capture_sheet.dart';

T? _maybeReadBloc<T extends StateStreamableSource<Object?>>(
  BuildContext context,
) {
  try {
    return context.read<T>();
  } catch (_) {
    return null;
  }
}

String _resolveCurrentLocation(BuildContext context) {
  try {
    return GoRouterState.of(context).uri.toString();
  } catch (_) {
    return '/today';
  }
}

class _LogoDrawerFeatureItem {
  final String id;
  final String tabKey;
  final String sectionTitle;
  final String title;
  final String subtitle;
  final String keywords;
  final IconData icon;
  final LifeOsAccentTone tone;
  final String route;
  final bool isShellTab;

  const _LogoDrawerFeatureItem({
    required this.id,
    required this.tabKey,
    required this.sectionTitle,
    required this.title,
    required this.subtitle,
    required this.keywords,
    required this.icon,
    required this.tone,
    required this.route,
    this.isShellTab = false,
  });
}

/// Opens the flagship LifeOS left-to-right slide-over navigation drawer when tapping
/// the top-left LifeOS Logo (or swiping from the left edge).
Future<void> showLifeOsLogoSideDrawer(BuildContext context) async {
  final authBloc = _maybeReadBloc<AuthBloc>(context);
  final dashBloc = _maybeReadBloc<DashboardBloc>(context);
  final dailyBloc = _maybeReadBloc<DailyLifeBloc>(context);
  final taskBloc = _maybeReadBloc<TaskBloc>(context);
  final familyBloc = _maybeReadBloc<FamilyBloc>(context);
  final vehicleBloc = _maybeReadBloc<VehicleBloc>(context);
  final currentLocation = _resolveCurrentLocation(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Đóng ngăn tính năng LifeOS',
    barrierColor: Colors.black.withValues(alpha: isDark ? 0.62 : 0.36),
    transitionDuration: const Duration(milliseconds: 270),
    pageBuilder: (dialogCtx, _, __) {
      return _LifeOsLogoSideDrawerSheet(
        parentContext: context,
        currentLocation: currentLocation,
        authBloc: authBloc,
        dashBloc: dashBloc,
        dailyBloc: dailyBloc,
        taskBloc: taskBloc,
        familyBloc: familyBloc,
        vehicleBloc: vehicleBloc,
      );
    },
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1.0, 0.0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _LifeOsLogoSideDrawerSheet extends StatefulWidget {
  final BuildContext parentContext;
  final String currentLocation;
  final AuthBloc? authBloc;
  final DashboardBloc? dashBloc;
  final DailyLifeBloc? dailyBloc;
  final TaskBloc? taskBloc;
  final FamilyBloc? familyBloc;
  final VehicleBloc? vehicleBloc;

  const _LifeOsLogoSideDrawerSheet({
    required this.parentContext,
    required this.currentLocation,
    required this.authBloc,
    required this.dashBloc,
    required this.dailyBloc,
    required this.taskBloc,
    required this.familyBloc,
    required this.vehicleBloc,
  });

  @override
  State<_LifeOsLogoSideDrawerSheet> createState() =>
      _LifeOsLogoSideDrawerSheetState();
}

class _LifeOsLogoSideDrawerSheetState
    extends State<_LifeOsLogoSideDrawerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String _selectedTab = 'all';
  double _dragDx = 0.0;

  static const List<(String key, String label)> _tabs = [
    ('all', 'Tất cả'),
    ('core', 'Chính'),
    ('finance', 'Tài chính'),
    ('health', 'Sức khỏe'),
    ('home', 'Nhà & Xe'),
  ];

  static const List<_LogoDrawerFeatureItem> _catalog = [
    // 1. MÀN HÌNH CHÍNH & ĐIỀU HƯỚNG NHANH
    _LogoDrawerFeatureItem(
      id: 'today',
      tabKey: 'core',
      sectionTitle: 'Không gian chính',
      title: 'Trang chủ Hôm nay',
      subtitle: 'Tổng quan tài sản, nhắc việc & tiện ích ghim',
      keywords: 'trang chu hom nay tong quan inbox',
      icon: Icons.home_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/today',
      isShellTab: true,
    ),
    _LogoDrawerFeatureItem(
      id: 'finance_root',
      tabKey: 'core',
      sectionTitle: 'Không gian chính',
      title: 'Tài chính & Sổ thu chi',
      subtitle: 'Ví tiền, ngân sách tháng & phân tích dòng tiền',
      keywords: 'tai chinh so thu chi vi tien ngan sach',
      icon: Icons.account_balance_wallet_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/finance',
      isShellTab: true,
    ),
    _LogoDrawerFeatureItem(
      id: 'planning_root',
      tabKey: 'core',
      sectionTitle: 'Không gian chính',
      title: 'Lịch trình & Công việc',
      subtitle: 'Lịch tuần, tháng, năm & việc cần làm',
      keywords: 'lich trinh cong viec google calendar',
      icon: Icons.calendar_today_rounded,
      tone: LifeOsAccentTone.blue,
      route: '/planning',
      isShellTab: true,
    ),
    _LogoDrawerFeatureItem(
      id: 'family_root',
      tabKey: 'core',
      sectionTitle: 'Không gian chính',
      title: 'Gia đình & Chia tiền nhóm',
      subtitle: 'Chia hóa đơn, thành viên & mua sắm chung',
      keywords: 'gia dinh chia tien nhom thanh vien o ghep',
      icon: Icons.groups_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/family',
      isShellTab: true,
    ),
    _LogoDrawerFeatureItem(
      id: 'smart_capture',
      tabKey: 'core',
      sectionTitle: 'Không gian chính',
      title: 'Ghi nhanh thông minh',
      subtitle: 'Nhập tự nhiên thu chi, lịch hẹn, nước uống',
      keywords: 'ghi nhanh thong minh ai nhap cau tu nhien',
      icon: Icons.bolt_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/financial-ai',
    ),

    // 2. SỨC KHỎE, UỐNG NƯỚC & ĐỜI SỐNG HẰNG NGÀY
    _LogoDrawerFeatureItem(
      id: 'water_reminder',
      tabKey: 'health',
      sectionTitle: 'Sức khỏe · Uống nước & Bếp',
      title: 'Nhắc uống nước & Chạy ngầm',
      subtitle: 'Chuẩn theo cân nặng, chiều cao & báo màn hình khóa',
      keywords: 'uong nuoc nhac nuoc can nang chieu cao thong bao ngam',
      icon: Icons.water_drop_rounded,
      tone: LifeOsAccentTone.blue,
      route: '/health-hub?tab=water',
    ),
    _LogoDrawerFeatureItem(
      id: 'health_meds',
      tabKey: 'health',
      sectionTitle: 'Sức khỏe · Uống nước & Bếp',
      title: 'Tủ thuốc, BMI & Thẻ Y tế',
      subtitle: 'Chuông nhắc thuốc, huyết áp & thông tin khẩn cấp',
      keywords: 'tu thuoc uong thuoc bmi huyet ap the y te bhyt sos',
      icon: Icons.favorite_outline_rounded,
      tone: LifeOsAccentTone.coral,
      route: '/health-hub',
    ),
    _LogoDrawerFeatureItem(
      id: 'kitchen_groceries',
      tabKey: 'health',
      sectionTitle: 'Sức khỏe · Uống nước & Bếp',
      title: 'Bếp gia đình & Giỏ đi chợ',
      subtitle: 'Thực đơn hôm nay, giỏ chợ & hạn dùng tủ lạnh',
      keywords: 'bep di cho thuc don tu lanh nau an',
      icon: Icons.shopping_basket_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/kitchen-groceries',
    ),
    _LogoDrawerFeatureItem(
      id: 'habits_focus',
      tabKey: 'health',
      sectionTitle: 'Sức khỏe · Uống nước & Bếp',
      title: 'Thói quen & Đồng hồ tập trung',
      subtitle: 'Chuỗi kỷ luật hằng ngày & phiên làm việc sâu',
      keywords: 'thoi quen tap trung pomodoro ky luat',
      icon: Icons.local_fire_department_outlined,
      tone: LifeOsAccentTone.amber,
      route: '/habits-focus',
    ),
    _LogoDrawerFeatureItem(
      id: 'smart_notes',
      tabKey: 'health',
      sectionTitle: 'Sức khỏe · Uống nước & Bếp',
      title: 'Sổ tay & Nhật ký cảm xúc',
      subtitle: 'Ghi chú ghim nhanh & theo dõi tâm trạng',
      keywords: 'so tay ghi chu cam xuc nhat ky',
      icon: Icons.sticky_note_2_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/smart-notes-hub',
    ),

    // 3. TÀI CHÍNH CHUYÊN SÂU, NGÂN HÀNG & THUẾ LƯƠNG
    _LogoDrawerFeatureItem(
      id: 'bank_qr',
      tabKey: 'finance',
      sectionTitle: 'Tài chính · Ngân hàng & Thuế',
      title: 'Ngân hàng tự động & Mã QR',
      subtitle: 'Tự đọc biến động số dư & tạo mã VietQR nhận tiền',
      keywords: 'ngan hang tu dong ma qr vietqr bien dong so du',
      icon: Icons.qr_code_2_rounded,
      tone: LifeOsAccentTone.emerald,
      route: '/notifications-privacy',
    ),
    _LogoDrawerFeatureItem(
      id: 'finance_report',
      tabKey: 'finance',
      sectionTitle: 'Tài chính · Ngân hàng & Thuế',
      title: 'Báo cáo thu chi & Xuất CSV',
      subtitle: 'Biểu đồ tuần, tháng, năm & xuất sao kê',
      keywords: 'bao cao thu chi bieu do thong ke xuat csv sao ke',
      icon: Icons.bar_chart_rounded,
      tone: LifeOsAccentTone.blue,
      route: '/finance-report',
    ),
    _LogoDrawerFeatureItem(
      id: 'wealth_tools',
      tabKey: 'finance',
      sectionTitle: 'Tài chính · Ngân hàng & Thuế',
      title: 'Tách hóa đơn & Tính lãi vay',
      subtitle: 'Chia bill theo món, lịch trả góp & quỹ tự do',
      keywords: 'tach hoa don tinh lai vay tra gop 6 chiec lo',
      icon: Icons.calculate_outlined,
      tone: LifeOsAccentTone.blue,
      route: '/wealth-tools',
    ),
    _LogoDrawerFeatureItem(
      id: 'salary_tax',
      tabKey: 'finance',
      sectionTitle: 'Tài chính · Ngân hàng & Thuế',
      title: 'Tính lương Gross–Net & Thuế',
      subtitle: 'Bảo hiểm bắt buộc, giảm trừ gia cảnh & thuế TNCN',
      keywords: 'luong gross net thue tncn bhxh giam tru',
      icon: Icons.request_quote_outlined,
      tone: LifeOsAccentTone.purple,
      route: '/smart-notes-hub',
    ),
    _LogoDrawerFeatureItem(
      id: 'family_funds',
      tabKey: 'finance',
      sectionTitle: 'Tài chính · Ngân hàng & Thuế',
      title: 'Quỹ tích lũy & Tiết kiệm chung',
      subtitle: 'Theo dõi tiến độ mục tiêu tiết kiệm gia đình',
      keywords: 'quy chung tiet kiem tich luy muc tieu',
      icon: Icons.savings_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/family-funds',
    ),
    _LogoDrawerFeatureItem(
      id: 'subscriptions',
      tabKey: 'finance',
      sectionTitle: 'Tài chính · Ngân hàng & Thuế',
      title: 'Gói đăng ký & Hạn bảo hành',
      subtitle: 'Nhắc gia hạn dịch vụ tháng & bảo hành thiết bị',
      keywords: 'thue bao goi dang ky bao hanh netflix youtube',
      icon: Icons.radar_rounded,
      tone: LifeOsAccentTone.amber,
      route: '/subscriptions-warranty',
    ),
    _LogoDrawerFeatureItem(
      id: 'social_ledger',
      tabKey: 'finance',
      sectionTitle: 'Tài chính · Ngân hàng & Thuế',
      title: 'Sổ Hiếu Hỷ & Chuyến đi',
      subtitle: 'Mừng cưới, lễ Tết & danh sách hành lý du lịch',
      keywords: 'so hieu hy mung cuoi le tet du lich hanh ly',
      icon: Icons.card_giftcard_rounded,
      tone: LifeOsAccentTone.purple,
      route: '/social-ledger-travel',
    ),

    // 4. NHÀ CỬA, XE CỘ, BÁO THỨC & TIỆN ÍCH HỆ THỐNG
    _LogoDrawerFeatureItem(
      id: 'alarms',
      tabKey: 'home',
      sectionTitle: 'Nhà cửa · Xe cộ & Báo thức',
      title: 'Báo thức & Chuông nhắc lịch',
      subtitle: 'Đặt báo thức cá nhân chuẩn từng phút & lặp thứ',
      keywords: 'bao thuc chuong hen gio thuc day',
      icon: Icons.alarm_on_rounded,
      tone: LifeOsAccentTone.coral,
      route: '/event-alarm',
    ),
    _LogoDrawerFeatureItem(
      id: 'tasks_board',
      tabKey: 'home',
      sectionTitle: 'Nhà cửa · Xe cộ & Báo thức',
      title: 'Bảng quản lý công việc',
      subtitle: 'Phân việc theo độ ưu tiên & hạn hoàn thành',
      keywords: 'bang cong viec viec can lam phan cong',
      icon: Icons.task_alt_rounded,
      tone: LifeOsAccentTone.blue,
      route: '/tasks-board',
    ),
    _LogoDrawerFeatureItem(
      id: 'vehicles',
      tabKey: 'home',
      sectionTitle: 'Nhà cửa · Xe cộ & Báo thức',
      title: 'Xe máy, Ô tô & Bảo dưỡng',
      subtitle: 'Theo dõi ODO thay nhớt, nước mát & bảo hiểm xe',
      keywords: 'xe may o to bao duong thay nhot odo dang kiem',
      icon: Icons.two_wheeler_rounded,
      tone: LifeOsAccentTone.blue,
      route: '/assets',
    ),
    _LogoDrawerFeatureItem(
      id: 'evn_home',
      tabKey: 'home',
      sectionTitle: 'Nhà cửa · Xe cộ & Báo thức',
      title: 'Điện nước EVN & Hợp đồng nhà',
      subtitle: 'Tính điện bậc thang, tiền phòng & lịch bảo trì',
      keywords: 'dien nuoc evn cong to hop dong thue nha wifi',
      icon: Icons.electric_bolt_rounded,
      tone: LifeOsAccentTone.amber,
      route: '/home-living',
    ),
    _LogoDrawerFeatureItem(
      id: 'documents',
      tabKey: 'home',
      sectionTitle: 'Nhà cửa · Xe cộ & Báo thức',
      title: 'Kho Giấy tờ & Hạn hiệu lực',
      subtitle: 'Lưu căn cước, hộ chiếu, bảo hiểm & hợp đồng',
      keywords: 'kho giay to tai lieu can cuoc ho chieu bao hiem',
      icon: Icons.folder_open_rounded,
      tone: LifeOsAccentTone.purple,
      route: '/family-documents',
    ),
    _LogoDrawerFeatureItem(
      id: 'home_widgets',
      tabKey: 'home',
      sectionTitle: 'Nhà cửa · Xe cộ & Báo thức',
      title: 'Widget ngoài màn hình chính',
      subtitle: 'Ghim số dư, chi tiêu an toàn & nút thu âm nhanh',
      keywords: 'widget man hinh chinh ghim giong noi',
      icon: Icons.widgets_outlined,
      tone: LifeOsAccentTone.emerald,
      route: '/home-widgets',
    ),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _resetFilters() {
    setState(() {
      _searchCtrl.clear();
      _query = '';
      _selectedTab = 'all';
    });
  }

  void _navigateToRoute(String route, {required bool isShellTab}) {
    Navigator.of(context).pop();
    if (!widget.parentContext.mounted) return;
    if (isShellTab) {
      widget.parentContext.go(route);
    } else {
      widget.parentContext.push(route);
    }
  }

  bool _isRouteActive(_LogoDrawerFeatureItem item) {
    final cur = widget.currentLocation;
    if (item.route.contains('?')) {
      return cur == item.route;
    }
    final curPath = cur.split('?').first;
    if (item.id == 'health_meds' && cur.contains('tab=water')) {
      return false;
    }
    if (item.id == 'salary_tax') {
      return false;
    }
    return curPath == item.route;
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final drawerWidth = math.min(mq.size.width * 0.90, 352.0);

    final user = widget.authBloc?.state.user;
    final dash = widget.dashBloc?.state.data ?? TodayDashboardEntity.empty;
    final daily = widget.dailyBloc?.state.snapshot ?? DailyLifeSnapshot.empty;
    final openTasksCount =
        widget.taskBloc?.state.tasks
            .where((t) => t.status != TaskWorkflowStatus.done)
            .length ??
        0;
    final activeFamilyName = widget.familyBloc?.state.activeFamily?.name;
    final vehiclesCount = widget.vehicleBloc?.state.vehicles.length ?? 0;

    final fullName = (user?.fullName ?? 'Người dùng LifeOS').trim();
    final initials = fullName.isEmpty
        ? 'L'
        : fullName
              .split(RegExp(r'\s+'))
              .where((p) => p.isNotEmpty)
              .map((p) => p.characters.first.toUpperCase())
              .take(2)
              .join();

    final q = _query.trim();
    final hasActiveFilters = _selectedTab != 'all' || q.isNotEmpty;
    final filtered = _catalog.where((item) {
      if (_selectedTab != 'all' && item.tabKey != _selectedTab) {
        return false;
      }
      if (q.isEmpty) return true;
      return VietnameseSearchMatcher.matchesAny(q, [
        item.title,
        item.subtitle,
        item.keywords,
        item.sectionTitle,
      ]);
    }).toList();

    final grouped = <String, List<_LogoDrawerFeatureItem>>{};
    for (final item in filtered) {
      grouped.putIfAbsent(item.sectionTitle, () => []).add(item);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          final next = (_dragDx + details.delta.dx).clamp(-drawerWidth, 0.0);
          setState(() => _dragDx = next);
        },
        onHorizontalDragEnd: (details) {
          final vx = details.primaryVelocity ?? 0.0;
          if (_dragDx < -64 || vx < -360) {
            Navigator.of(context).pop();
          } else {
            setState(() => _dragDx = 0.0);
          }
        },
        child: Transform.translate(
          offset: Offset(_dragDx, 0),
          child: SizedBox(
            key: const Key('lifeos_logo_side_drawer'),
            width: drawerWidth,
            height: mq.size.height,
            child: Material(
              color: c.surface,
              elevation: 18,
              shadowColor: Colors.black.withValues(alpha: isDark ? 0.55 : 0.18),
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(26),
                ),
                side: BorderSide(
                  color: c.border.withValues(alpha: isDark ? 0.75 : 0.9),
                  width: 0.9,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Brand Header + Voice + Close Button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: LifeOsBrandWordmark(
                                  iconSize: 28,
                                  fontSize: 18.5,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('logo_drawer_voice_btn'),
                            tooltip: 'Thu âm ghi nhanh',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              Navigator.of(context).pop();
                              if (widget.parentContext.mounted) {
                                showVoiceSmartCaptureSheet(
                                  widget.parentContext,
                                  autoStartListening: true,
                                );
                              }
                            },
                            icon: Icon(
                              Icons.mic_rounded,
                              size: 20,
                              color: c.primary,
                            ),
                          ),
                          IconButton(
                            key: const Key('logo_drawer_close_btn'),
                            tooltip: 'Đóng bảng tính năng',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.close_rounded,
                              size: 21,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 2. Compact Account & Real-Time Daily Pulse Card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Material(
                        color: c.surfaceRaised,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: const Key('logo_drawer_profile_card'),
                          onTap: () => _navigateToRoute(
                            '/account-profile',
                            isShellTab: false,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(11),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(11),
                                        gradient: const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: LifeOSBrandColors
                                              .appIconBgGradient,
                                        ),
                                      ),
                                      child: Text(
                                        initials,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            fullName,
                                            softWrap: true,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w800,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                          Text(
                                            activeFamilyName != null &&
                                                    activeFamilyName.isNotEmpty
                                                ? 'Không gian: $activeFamilyName'
                                                : 'Không gian cá nhân',
                                            softWrap: true,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: c.textSecondary,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    LifeOsStatusPill(
                                      icon: Icons
                                          .account_balance_wallet_outlined,
                                      label:
                                          'Ví: ${VndAmount.format(dash.netWorthMinor)}',
                                      tone: LifeOsAccentTone.emerald,
                                    ),
                                    LifeOsStatusPill(
                                      icon: Icons.water_drop_outlined,
                                      label:
                                          'Nước: ${daily.hydration.waterMl}/${daily.hydration.targetWaterMl} ml',
                                      tone: LifeOsAccentTone.blue,
                                    ),
                                    if (openTasksCount > 0)
                                      LifeOsStatusPill(
                                        icon: Icons.task_alt_rounded,
                                        label: '$openTasksCount việc mở',
                                        tone: LifeOsAccentTone.amber,
                                      )
                                    else if (vehiclesCount > 0)
                                      LifeOsStatusPill(
                                        icon: Icons.two_wheeler_rounded,
                                        label: '$vehiclesCount xe',
                                        tone: LifeOsAccentTone.neutral,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 3. Instant Vietnamese Unaccented Search
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        key: const Key('logo_drawer_search_input'),
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Tìm nhanh tính năng',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 19,
                          ),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  key: const Key(
                                    'logo_drawer_search_clear_btn',
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
                    ),
                    const SizedBox(height: 8),

                    // 4. Category Pill Tabs ("Tất cả · Chính · Tài chính · Sức khỏe · Nhà & Xe")
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tab in _tabs)
                            ChoiceChip(
                              key: Key('logo_drawer_tab_${tab.$1}'),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              label: Text(
                                tab.$2,
                                style: const TextStyle(fontSize: 11.8),
                              ),
                              selected: tab.$1 == 'all'
                                  ? !hasActiveFilters
                                  : _selectedTab == tab.$1,
                              onSelected: (_) {
                                if (tab.$1 == 'all') {
                                  _resetFilters();
                                } else {
                                  setState(() {
                                    _selectedTab = _selectedTab == tab.$1
                                        ? 'all'
                                        : tab.$1;
                                  });
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Divider(height: 1, thickness: 0.7, color: c.separator),

                    // 5. Scannable Feature List with Active Highlight
                    Expanded(
                      child: grouped.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off_rounded,
                                      size: 36,
                                      color: c.textSecondary,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Không tìm thấy tính năng phù hợp',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    FilledButton.tonalIcon(
                                      key: const Key('logo_drawer_reset_btn'),
                                      onPressed: _resetFilters,
                                      icon: const Icon(
                                        Icons.filter_alt_off_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Xem tất cả tính năng'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView(
                              key: const Key('logo_drawer_feature_list'),
                              padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                              children: [
                                for (final section in grouped.entries) ...[
                                  if (_selectedTab == 'all')
                                    LifeOsSectionHeader(
                                      title: section.key,
                                      padding: const EdgeInsets.only(
                                        top: 10,
                                        bottom: 6,
                                        left: 2,
                                        right: 2,
                                      ),
                                    )
                                  else
                                    const SizedBox(height: 4),
                                  for (final item in section.value)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 7),
                                      child: _DrawerFeatureRow(
                                        item: item,
                                        isActive: _isRouteActive(item),
                                        onTap: () => _navigateToRoute(
                                          item.route,
                                          isShellTab: item.isShellTab,
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                    ),

                    // 6. Quick Utility Footer Bar
                    Divider(height: 1, thickness: 0.7, color: c.separator),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            key: const Key('logo_drawer_theme_btn'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                              if (widget.parentContext.mounted) {
                                showLifeOsAppearanceSheet(widget.parentContext);
                              }
                            },
                            icon: Icon(
                              isDark
                                  ? Icons.light_mode_outlined
                                  : Icons.dark_mode_outlined,
                              size: 17,
                            ),
                            label: const Text('Giao diện'),
                          ),
                          TextButton.icon(
                            key: const Key('logo_drawer_all_services_btn'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _navigateToRoute(
                              '/super-app-hub',
                              isShellTab: false,
                            ),
                            icon: const Icon(Icons.grid_view_rounded, size: 17),
                            label: const Text('Tất cả 360°'),
                          ),
                          TextButton.icon(
                            key: const Key('logo_drawer_settings_btn'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _navigateToRoute(
                              '/settings-hub',
                              isShellTab: false,
                            ),
                            icon: const Icon(Icons.settings_outlined, size: 17),
                            label: const Text('Cài đặt'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerFeatureRow extends StatelessWidget {
  final _LogoDrawerFeatureItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _DrawerFeatureRow({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Material(
      color: isActive ? c.primarySubtle : c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive
              ? c.primary.withValues(alpha: 0.45)
              : c.border.withValues(alpha: 0.55),
          width: isActive ? 1.1 : 0.7,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('logo_drawer_item_${item.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              LifeOsIconSquircle(
                icon: item.icon,
                tone: item.tone,
                size: 36,
                iconSize: 18,
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
                        fontSize: 13.2,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        color: isActive ? c.primary : c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 11.4,
                        height: 1.24,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                isActive
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                size: 18,
                color: isActive ? c.primary : c.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
