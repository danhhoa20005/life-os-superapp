import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../bloc/pro_utilities_bloc.dart';

/// Unified Hub surfacing all Paid-Market Replacement Suites natively inside LifeOS (`0₫`).
class ProUtilitiesHubPage extends StatelessWidget {
  const ProUtilitiesHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final proState = context.watch<ProUtilitiesBloc>().state;
    final dashData = context.watch<DashboardBloc>().state.data;

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              const LifeOsTopBrandHeader(
                title: 'Tiện ích Pro Tích hợp',
                subtitle:
                    'Trọn bộ công cụ cao cấp thường phải thuê bao trả phí — miễn phí 100% trong LifeOS.',
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
                        // 1. Value Proposition Hero Card
                        LifeOsMintHeroCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const LifeOsIconSquircle(
                                    icon: Icons.workspace_premium_rounded,
                                    tone: LifeOsAccentTone.emerald,
                                    solidFill: true,
                                    size: 46,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Bộ 4 Siêu Tiện Ích Đời Sống & Tiền Bạc',
                                          style: TextStyle(
                                            fontSize: 16.5,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Thay thế 6 app trả phí rời rạc (tiết kiệm ~350.000 ₫/tháng)',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 22),
                              IntrinsicHeight(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _MiniHubMetric(
                                        label: 'Đốt ngầm/tháng',
                                        value: VndAmount.formatCompact(
                                          proState.totalMonthlySubBurnMinor,
                                        ),
                                        color: c.primary,
                                      ),
                                    ),
                                    VerticalDivider(width: 12, color: c.separator),
                                    Expanded(
                                      child: _MiniHubMetric(
                                        label: 'Nước & Tập trung',
                                        value:
                                            '${proState.todayWellness.waterMl}ml · ${proState.todayWellness.focusMinutes}p',
                                        color: c.primary,
                                      ),
                                    ),
                                    VerticalDivider(width: 12, color: c.separator),
                                    Expanded(
                                      child: _MiniHubMetric(
                                        label: 'Sổ Hiếu Hỷ',
                                        value: '${proState.giftEntries.length} mục',
                                        color: c.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Module 1: Subscription & Appliance Warranty Radar
                        _ProSuiteModuleCard(
                          icon: Icons.radar_rounded,
                          tone: LifeOsAccentTone.emerald,
                          replacesBadge: 'Thay thế Rocket Money / Bobby',
                          title: 'Radar Gói Đăng ký & Phiếu Bảo hành',
                          subtitle:
                              'Phát hiện chi phí trừ ngầm hằng tháng/năm, nhắc hủy trước khi gia hạn & đếm ngược hạn bảo hành điện máy.',
                          metricLine:
                              '${proState.subscriptionsOnly.length} gói đăng ký · ${proState.warrantiesOnly.length} phiếu bảo hành',
                          onTap: () => context.push('/subscriptions-warranty'),
                        ),
                        const SizedBox(height: 12),

                        // Module 2: Receipt Scanner, Loan Amortization & FIRE Simulator
                        _ProSuiteModuleCard(
                          icon: Icons.calculate_outlined,
                          tone: LifeOsAccentTone.blue,
                          replacesBadge: 'Thay thế YNAB / Monarch / Bill OCR',
                          title: 'Quét Bill AI, Tính Lãi Vay & Tự do FIRE',
                          subtitle:
                              'Bóc tách hóa đơn nhiều món 1 chạm, tính dư nợ giảm dần vay mua nhà/xe & lộ trình nghỉ hưu sớm 4% + 6 Chiếc Lọ.',
                          metricLine:
                              'Tài sản ròng hiện tại: ${VndAmount.format(dashData.netWorthMinor)}',
                          onTap: () => context.push('/wealth-tools'),
                        ),
                        const SizedBox(height: 12),

                        // Module 3: Habit Streaks, Hydration & Pomodoro Deep Focus
                        _ProSuiteModuleCard(
                          icon: Icons.local_fire_department_outlined,
                          tone: LifeOsAccentTone.amber,
                          replacesBadge: 'Thay thế Habitify / Forest / Waterllama',
                          title: 'Chuỗi Thói quen, Uống Nước & Pomodoro',
                          subtitle:
                              'Xây dựng chuỗi ngày không chi tiêu thừa, đồng hồ tập trung sâu 25p/45p và nhắc uống đủ 2.000ml nước mỗi ngày.',
                          metricLine:
                              '${proState.habits.length} thói quen · ${proState.todayWellness.completedPomodoros} phiên Pomodoro hôm nay',
                          onTap: () => context.push('/habits-focus'),
                        ),
                        const SizedBox(height: 12),

                        // Module 4: Vietnamese Gift/Wedding Reciprocity Ledger & Smart Trip Packing
                        _ProSuiteModuleCard(
                          icon: Icons.card_giftcard_rounded,
                          tone: LifeOsAccentTone.purple,
                          replacesBadge: 'Thay thế Sổ Hiếu Hỷ Pro & Tripsy',
                          title: 'Sổ Hiếu Hỷ "Có Đi Có Lại" & Hành lý Du lịch',
                          subtitle:
                              'Tra cứu tức thì tiền mừng cưới/tân gia/lễ Tết hai chiều để đáp lễ tinh tế, kèm mẫu checklist hành lý 1 chạm.',
                          metricLine:
                              'Đi mừng: ${VndAmount.formatCompact(proState.totalGiftGaveMinor)} · Nhận: ${VndAmount.formatCompact(proState.totalGiftReceivedMinor)}',
                          onTap: () => context.push('/social-ledger-travel'),
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

class _MiniHubMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniHubMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: c.textSecondary),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ProSuiteModuleCard extends StatelessWidget {
  final IconData icon;
  final LifeOsAccentTone tone;
  final String replacesBadge;
  final String title;
  final String subtitle;
  final String metricLine;
  final VoidCallback onTap;

  const _ProSuiteModuleCard({
    required this.icon,
    required this.tone,
    required this.replacesBadge,
    required this.title,
    required this.subtitle,
    required this.metricLine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return LifeOsSoftCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LifeOsIconSquircle(icon: icon, tone: tone, size: 46, iconSize: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LifeOsStatusPill(label: replacesBadge, tone: tone),
                    const SizedBox(height: 5),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textSecondary),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              height: 1.38,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_graph_rounded, size: 15, color: c.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    metricLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.2,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
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
