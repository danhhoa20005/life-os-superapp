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
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/voice_smart_capture_sheet.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../bloc/dashboard_bloc.dart';

/// Google Material You (Material 3) AppWidget Studio & Zero-Touch Auto-Sync Hub.
class HomeWidgetsStudioPage extends StatelessWidget {
  const HomeWidgetsStudioPage({super.key});

  Future<void> _pinWidget(
    BuildContext context,
    String kind,
    String title,
  ) async {
    final ok = await sl<NativeHomeWidgetBridge>().requestPinWidget(kind);
    if (!context.mounted) return;
    LifeOsTopToast.fromSnackBar(
      context,
      SnackBar(
        content: Text(
          ok
              ? '✓ Đã mở hộp thoại hệ thống Google Android để ghim "$title"!'
              : 'Nhấn giữ ngoài Màn hình chính Android → Tiện ích (Widgets) → Life OS để đặt "$title".',
        ),
      ),
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
      wealthBadge: autoConfirm ? 'Auto-Ledger' : 'Auto-Sync',
      groupTitle: groupTitle,
      groupStatus: 'Chia tiền ăn uống, việc nhà, điện nước 1 chạm',
      runwayLabel: runwayLabel,
      dailyUsedPct: usedPct,
    );
    if (!context.mounted) return;
    LifeOsTopToast.fromSnackBar(
      context,
      const SnackBar(
        content: Text(
          '✓ Đã đồng bộ số liệu mới nhất ra cả 4 Widget Màn hình chính!',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
    final usedPct = dash.dailySafeToSpendMinor > 0
        ? ((dash.todayExpenseMinor * 100) ~/ dash.dailySafeToSpendMinor).clamp(
            5,
            100,
          )
        : 15;
    final groupTitle = family != null
        ? '${family.name} · ${family.members.length} thành viên'
        : 'Tổ ấm & Hội nhóm';
    final runwayLabel =
        'Quỹ dự phòng: ${runway.monthsOfRunway.toStringAsFixed(1)} tháng · ${runway.statusBadge}';

    // Exact Google Material 3 Widget Surface Tokens (matches res/values & res/values-night)
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
                            // 1. Compact Zero-Touch Auto-Sync Card
                            LifeOsMintHeroCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.sync_rounded,
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
                                              'Tự Động Cập Nhật Số Liệu Ra Widget',
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              'Tự bắt biến động số dư ngân hàng ngay cả khi đóng app',
                                              style: TextStyle(
                                                fontSize: 11.8,
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
                                          onPressed: () => _forceSyncAllWidgets(
                                            context,
                                            autoConfirm: autoConfirm,
                                            groupTitle: groupTitle,
                                            runwayLabel: runwayLabel,
                                            usedPct: usedPct,
                                          ),
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                            size: 17,
                                          ),
                                          label: const Text('Đồng bộ Widget'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => context.push(
                                            '/notifications-privacy',
                                          ),
                                          icon: const Icon(
                                            Icons.cloud_sync_outlined,
                                            size: 17,
                                          ),
                                          label: const Text(
                                            'Cổng QR & Ngân hàng',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 2. WIDGET 01: Google Pixel Search & Voice Quick Bar (4x1)
                            _GoogleM3WidgetShowcaseCard(
                              badgeLabel:
                                  'WIDGET 01 · 4×1 · THANH TÌM KIẾM & GIỌNG NÓI PIXEL',
                              description:
                                  'Chạm mic nói nhanh chi tiêu hoặc chia tiền nhóm.',
                              surfaceColor: m3WidgetSurface,
                              strokeColor: m3Stroke,
                              onPin: () => _pinWidget(
                                context,
                                'voice',
                                'Thanh Tìm kiếm & Giọng nói AI',
                              ),
                              widgetPreview: Row(
                                children: [
                                  const LifeOsLeafMark(
                                    size: 28,
                                    borderRadius: 9,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () =>
                                          showVoiceSmartCaptureSheet(context),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: m3TonalBox,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Nói chi tiêu hoặc chia tiền...',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              'Chi hôm nay: ${VndAmount.format(dash.todayExpenseMinor)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
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
                                  const SizedBox(width: 8),
                                  InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () => showVoiceSmartCaptureSheet(
                                      context,
                                      autoStartListening: true,
                                    ),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: c.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.mic_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () => showVoiceSmartCaptureSheet(
                                      context,
                                      initialTranscript:
                                          'Ăn lẩu bò 450 nghìn chia đều 3 người',
                                    ),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: m3TonalPillBg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.groups_rounded,
                                        color: m3TonalPillFg,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 3. WIDGET 02: Google Finance / Google Wallet Net Worth Card (4x2)
                            _GoogleM3WidgetShowcaseCard(
                              badgeLabel: 'WIDGET 02 · 4×2 · TÀI SẢN & THU CHI',
                              description:
                                  'Xem số dư và thu chi tháng ngay ngoài màn hình chính.',
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
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          'Tài sản & Dòng tiền',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: m3TonalPillBg,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          autoConfirm
                                              ? 'Auto-Ledger'
                                              : 'Auto-Sync',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: m3TonalPillFg,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () => context.go('/finance'),
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: m3TonalPillBg,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.add_rounded,
                                            size: 17,
                                            color: m3TonalPillFg,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    VndAmount.format(dash.netWorthMinor),
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            color: m3IncomeBox,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Thu tháng',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  color: c.textSecondary,
                                                ),
                                              ),
                                              Text(
                                                '+${VndAmount.format(dash.monthlyIncomeMinor)}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12.2,
                                                  fontWeight: FontWeight.w800,
                                                  color: c.primary,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            color: m3ExpenseBox,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Chi tháng',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  color: c.textSecondary,
                                                ),
                                              ),
                                              Text(
                                                '-${VndAmount.format(dash.monthlyExpenseMinor)}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12.2,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFFDC2626),
                                                  fontFeatures: [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // 4. WIDGET 03: Google Keep / Tasks Family & Roommate Split Hub (4x2)
                            _GoogleM3WidgetShowcaseCard(
                              badgeLabel:
                                  'WIDGET 03 · 4×2 · CHIA TIỀN NHÓM & GIA ĐÌNH',
                              description:
                                  'Nói câu chia tiền nhóm và mở nhanh mã QR thanh toán.',
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
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          groupTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Chia tiền ăn uống, việc nhà, điện nước 1 chạm',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.8,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          onTap: () => showVoiceSmartCaptureSheet(
                                            context,
                                            initialTranscript:
                                                'Tiền điện nước 1 triệu 2 chia cho Hòa, Minh và Lan',
                                          ),
                                          child: Container(
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: c.primary,
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                            ),
                                            child: const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.mic_rounded,
                                                  size: 17,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    'Nói chia tiền',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 4,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          onTap: () => context.go('/family'),
                                          child: Container(
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: m3TonalPillBg,
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.groups_rounded,
                                                  size: 17,
                                                  color: m3TonalPillFg,
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    'Tất toán QR',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: m3TonalPillFg,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
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
                                ],
                              ),
                            ),

                            // 5. WIDGET 04: Google Digital Wellbeing Safe Daily Spend (3x2)
                            _GoogleM3WidgetShowcaseCard(
                              badgeLabel:
                                  'WIDGET 04 · 3×2 · HẠN MỨC CHI TIÊU HÔM NAY',
                              description:
                                  'Theo dõi số tiền an toàn có thể tiêu trong ngày.',
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
                                        Icons.verified_user_rounded,
                                        size: 18,
                                        color: c.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Hạn mức hôm nay',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: m3TonalPillBg,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          'Đã dùng $usedPct%',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: m3TonalPillFg,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    VndAmount.format(
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
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      minHeight: 10,
                                      value: (usedPct / 100).clamp(0.06, 1.0),
                                      color: c.primary,
                                      backgroundColor: isDark
                                          ? const Color(0xFF2D3748)
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    runwayLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                  label: const Text('Ghim Widget'),
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
