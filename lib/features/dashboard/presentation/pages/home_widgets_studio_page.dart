import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/services/native_home_widget_bridge.dart';
import '../../../../core/utils/smart_quick_entry_parser.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/voice_smart_capture_sheet.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../bloc/dashboard_bloc.dart';

class HomeWidgetsStudioPage extends StatelessWidget {
  const HomeWidgetsStudioPage({super.key});

  Future<void> _pinWidget(BuildContext context, String kind, String title) async {
    final ok = await sl<NativeHomeWidgetBridge>().requestPinWidget(kind);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '✓ Đã mở hộp thoại Ghim "$title" ra Màn hình chính Android!'
              : 'Mẹo: Nhấn giữ ngoài Màn hình chính Android → Chọn Tiện ích (Widgets) → Life OS để đặt "$title".',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dash = context.watch<DashboardBloc>().state.data;
    final family = context.watch<FamilyBloc>().state.activeFamily;
    final runway = EmergencyRunwaySnapshot.compute(
      netLiquidMinor: dash.netWorthMinor,
      monthlyExpenseMinor: dash.monthlyExpenseMinor,
    );

    return Scaffold(
      appBar: LiquidGlassBar(
        title: const Text('Tự động Cập nhật & 4 Widget Màn Hình Chính'),
        actions: [
          IconButton(
            tooltip: 'Mở Trợ lý Giọng nói AI',
            onPressed: () => showVoiceSmartCaptureSheet(context),
            icon: const Icon(Icons.mic_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<NotificationIngestionBloc, NotificationIngestionState>(
          builder: (context, notifState) {
            final consent = notifState.consent;
            final notifEnabled = consent?.enabled ?? false;
            final autoConfirm = consent?.autoConfirmSignals ?? false;
            final allowedPkgs = consent?.allowedPackages ??
                kSupportedVnBanks.map((b) => b.packageName).toList();

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    // SECTION 1: ZERO-MANUAL-ENTRY AUTONOMOUS ENGINE
                    ProHeroGradientCard(
                      gradientColors: const [
                        Color(0xFF064E1E),
                        Color(0xFF0B7A2A),
                        Color(0xFF0A2240),
                      ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(
                                  Icons.bolt_rounded,
                                  color: Color(0xFF8CE99A),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Cơ chế Tự Cập Nhật Không Cần Ghi Tay',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      'Tự bắt thông báo ngân hàng kể cả khi đóng app, tự đồng bộ SePay & bóc tách giọng nói AI',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.82),
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  activeThumbColor: const Color(0xFF8CE99A),
                                  title: const Text(
                                    '1. Tự động bắt biến động số dư Ngân hàng & Ví',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    notifState.isNativePermissionGranted
                                        ? 'Đã cấp quyền hệ thống · Lưu hàng đợi cả khi tắt app'
                                        : 'Nhấn để bật & cấp quyền NotificationListener Android',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.75),
                                      fontSize: 11,
                                    ),
                                  ),
                                  value: notifEnabled,
                                  onChanged: (next) {
                                    context.read<NotificationIngestionBloc>().add(
                                          ConsentConfigUpdated(
                                            userId: user.id,
                                            enabled: next,
                                            allowedPackages: allowedPkgs.isEmpty
                                                ? kSupportedVnBanks
                                                    .map((b) => b.packageName)
                                                    .toList()
                                                : allowedPkgs,
                                            autoConfirmSignals: autoConfirm,
                                          ),
                                        );
                                    if (next && !notifState.isNativePermissionGranted) {
                                      context.read<NotificationIngestionBloc>().add(
                                            const OpenNativePermissionSettingsRequested(),
                                          );
                                    }
                                  },
                                ),
                                Divider(color: Colors.white.withValues(alpha: 0.14), height: 8),
                                SwitchListTile(
                                  key: const Key('zero_touch_auto_confirm_switch'),
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  activeThumbColor: const Color(0xFF8CE99A),
                                  title: const Text(
                                    '2. Tự ghi thẳng vào Sổ cái (Không cần bấm duyệt)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    autoConfirm
                                        ? 'Đang BẬT: Cộng/trừ thẳng số dư ví & cập nhật Widget tự động'
                                        : 'Đang giữ ở chế độ chờ duyệt thủ công (PROVISIONAL)',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.75),
                                      fontSize: 11,
                                    ),
                                  ),
                                  value: autoConfirm,
                                  onChanged: (next) {
                                    context.read<NotificationIngestionBloc>().add(
                                          ConsentConfigUpdated(
                                            userId: user.id,
                                            enabled: next ? true : notifEnabled,
                                            allowedPackages: allowedPkgs.isEmpty
                                                ? kSupportedVnBanks
                                                    .map((b) => b.packageName)
                                                    .toList()
                                                : allowedPkgs,
                                            autoConfirmSignals: next,
                                          ),
                                        );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => showVoiceSmartCaptureSheet(
                                    context,
                                    autoStartListening: true,
                                  ),
                                  icon: const Icon(Icons.mic_rounded, size: 18),
                                  label: const Text('Nói Ghi / Chia'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                                    side: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  onPressed: () => context.push('/notifications-privacy'),
                                  icon: const Icon(Icons.cloud_sync_rounded, size: 18),
                                  label: const Text('SePay Auto-API'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Bộ 4 Widget Ngoài Màn Hình Chính Android',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Thiết kế chuyên biệt cho 4 mục đích thực tế. Nhấn "Ghim ra Màn hình chính" để đặt ngay lên màn hình điện thoại của bạn:',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // WIDGET PREVIEW 1: Voice Quick Bar (4x2)
                    _HomeWidgetPreviewCard(
                      indexLabel: 'WIDGET 01 · 4×2 · GHI & CHIA GIỌNG NÓI 1 CHẠM',
                      purpose:
                          'Dành cho người bận rộn: Bấm 1 chạm ngoài màn hình khóa/chính để đọc câu thu chi hoặc chia bill tức thì.',
                      gradient: const [Color(0xFF0F172A), Color(0xFF0B2E22), Color(0xFF064E3B)],
                      onPin: () =>
                          _pinWidget(context, 'voice', 'Trợ lý Giọng nói & Ghi nhanh'),
                      previewBody: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'LIFE OS · TRỢ LÝ GIỌNG NÓI AI',
                                style: TextStyle(
                                  color: Color(0xFF8CE99A),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Hôm nay: ${VndAmount.format(dash.todayExpenseMinor)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'VD: “Ăn lẩu 450k chia đều 3 người” · “Phở 65k”',
                            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: InkWell(
                                  onTap: () => showVoiceSmartCaptureSheet(
                                    context,
                                    autoStartListening: true,
                                  ),
                                  child: Container(
                                    height: 38,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      '🎙 Nói Ghi / Chia',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: InkWell(
                                  onTap: () => showVoiceSmartCaptureSheet(
                                    context,
                                    initialTranscript:
                                        'Ăn lẩu bò 450 nghìn chia đều 3 người',
                                  ),
                                  child: Container(
                                    height: 38,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      '⇄ Chia nhóm',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11.5,
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

                    // WIDGET PREVIEW 2: Wealth Net Worth (4x2)
                    _HomeWidgetPreviewCard(
                      indexLabel: 'WIDGET 02 · 4×2 · TỔNG TÀI SẢN & DÒNG TIỀN PRIVATE BANKING',
                      purpose:
                          'Dành cho quản trị tài sản cá nhân: Quan sát Tổng tài sản ròng, Thu/Chi tháng và số biến động tự bắt.',
                      gradient: const [Color(0xFF064E1E), Color(0xFF0B7A2A), Color(0xFF0E9447)],
                      onPin: () => _pinWidget(context, 'wealth', 'Tổng Tài Sản & Dòng Tiền'),
                      previewBody: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'TỔNG TÀI SẢN RÒNG · LIFE OS',
                                style: TextStyle(
                                  color: Color(0xFFD1FAE5),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  autoConfirm ? 'Auto-Ledger BẬT' : 'Auto-Sync',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            VndAmount.format(dash.netWorthMinor),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '↓ Thu: +${VndAmount.format(dash.monthlyIncomeMinor)}',
                                style: const TextStyle(
                                  color: Color(0xFF86EFAC),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '↑ Chi: -${VndAmount.format(dash.monthlyExpenseMinor)}',
                                style: const TextStyle(
                                  color: Color(0xFFFDE68A),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // WIDGET PREVIEW 3: Group / Roommates / Family Split + VietQR (4x2)
                    _HomeWidgetPreviewCard(
                      indexLabel: 'WIDGET 03 · 4×2 · HỘI NHÓM, Ở GHÉP & GIA ĐÌNH + VIETQR',
                      purpose:
                          'Dành cho bạn cùng phòng, cặp đôi & hộ gia đình: Đọc 1 câu chia tiền ăn uống/điện nước/việc nhà và bật QR tất toán.',
                      gradient: const [Color(0xFF0A2240), Color(0xFF14427A), Color(0xFF1971C2)],
                      onPin: () => _pinWidget(context, 'group', 'Chia Tiền Nhóm & Gia Đình'),
                      previewBody: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            family != null
                                ? '${family.name.toUpperCase()} · ${family.members.length} THÀNH VIÊN'
                                : 'HỘI NHÓM & GIA ĐÌNH · CHIA TIỀN NHANH',
                            style: const TextStyle(
                              color: Color(0xFFBAE6FD),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Nói câu chia ăn uống, việc nhà, điện nước siêu tốc',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: InkWell(
                                  onTap: () => showVoiceSmartCaptureSheet(
                                    context,
                                    initialTranscript:
                                        'Tiền điện nước 1 triệu 2 chia cho Hòa, Minh và Lan',
                                  ),
                                  child: Container(
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: const Text(
                                      '🎙 Nói câu chia tiền',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: InkWell(
                                  onTap: () => context.go('/family'),
                                  child: Container(
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: const Text(
                                      'QR Tất toán',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11.5,
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

                    // WIDGET PREVIEW 4: Daily Safe-to-Spend & Emergency Runway (3x2)
                    _HomeWidgetPreviewCard(
                      indexLabel: 'WIDGET 04 · 3×2 · KỶ LUẬT HẠN MỨC NGÀY & QUỸ DỰ PHÒNG',
                      purpose:
                          'Dành cho người muốn kiểm soát kỷ luật tiêu dùng hằng ngày: Biết chính xác hôm nay còn được tiêu bao nhiêu.',
                      gradient: const [Color(0xFF181A20), Color(0xFF1E293B), Color(0xFF0F172A)],
                      onPin: () => _pinWidget(context, 'safe_spend', 'Hạn Mức An Toàn Hôm Nay'),
                      previewBody: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'HẠN MỨC AN TOÀN HÔM NAY',
                            style: TextStyle(
                              color: Color(0xFFFCD34D),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            VndAmount.format(dash.dailySafeToSpendMinor),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              minHeight: 6,
                              value: dash.dailySafeToSpendMinor > 0
                                  ? (dash.todayExpenseMinor / dash.dailySafeToSpendMinor)
                                      .clamp(0.06, 1.0)
                                  : 0.15,
                              color: const Color(0xFF10B981),
                              backgroundColor: Colors.white24,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Quỹ dự phòng: ${runway.monthsOfRunway.toStringAsFixed(1)} tháng (${runway.statusBadge})',
                            style: TextStyle(
                              color: c.surface == Colors.white
                                  ? const Color(0xFFCBD5E1)
                                  : Colors.white70,
                              fontSize: 11,
                            ),
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
    );
  }
}

class _HomeWidgetPreviewCard extends StatelessWidget {
  final String indexLabel;
  final String purpose;
  final List<Color> gradient;
  final Widget previewBody;
  final VoidCallback onPin;

  const _HomeWidgetPreviewCard({
    required this.indexLabel,
    required this.purpose,
    required this.gradient,
    required this.previewBody,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      indexLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
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
                    icon: const Icon(Icons.push_pin_rounded, size: 15),
                    label: const Text('Ghim ra màn hình'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(purpose, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.first.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: previewBody,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
