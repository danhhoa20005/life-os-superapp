import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../domain/entities/automation_entities.dart';
import '../bloc/automation_bloc.dart';

class AutomationStudioPage extends StatelessWidget {
  const AutomationStudioPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return BlocConsumer<AutomationBloc, AutomationState>(
      listenWhen: (p, n) =>
          p.feedbackMessage != n.feedbackMessage && n.feedbackMessage != null,
      listener: (ctx, state) {
        if (state.feedbackMessage != null) {
          LifeOsTopToast.show(ctx, state.feedbackMessage!);
        }
      },
      builder: (context, state) {
        return Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              child: Column(
                children: [
                  const LifeOsTopBrandHeader(
                    title: 'Tự động hóa Thông minh',
                    showBackButton: true,
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppSpacing.maxContentWidth,
                        ),
                        child: ListView(
                          key: const Key('automation_studio_list_view'),
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.xs,
                            AppSpacing.md,
                            AppSpacing.xxl,
                          ),
                          children: [
                            LifeOsMintHeroCard(
                              child: Row(
                                children: [
                                  const BananaGlassIcon(
                                    assetPath: AppAssets.ic3dAiSpark,
                                    fallbackIcon: Icons.auto_fix_high_rounded,
                                    size: 44,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Liên kết Sự kiện Đa mô-đun',
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Đang bật ${state.rules.where((r) => r.enabled).length}/${state.rules.length} quy tắc · Mọi thao tác luôn xin xác nhận & có chống lặp.',
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 12.4,
                                            color: c.textSecondary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (state.suggestions.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(
                                'Đề xuất đang chờ bạn xác nhận',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...state.suggestions.map(
                                (sug) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: LifeOsSoftCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          sug.headlineVi,
                                          softWrap: true,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          sug.detailVi,
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            FilledButton.tonalIcon(
                                              onPressed: () {
                                                context.read<AutomationBloc>().add(
                                                  AutomationSuggestionConfirmed(
                                                    sug,
                                                  ),
                                                );
                                                context.push(sug.targetRoute);
                                              },
                                              icon: const Icon(
                                                Icons.check_rounded,
                                                size: 17,
                                              ),
                                              label: const Text('Thực hiện'),
                                            ),
                                            OutlinedButton(
                                              onPressed: () {
                                                context.read<AutomationBloc>().add(
                                                  AutomationSuggestionDismissed(
                                                    sug.suggestionId,
                                                  ),
                                                );
                                              },
                                              child: const Text('Bỏ qua'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Text(
                              'Danh sách Quy tắc Tự động hóa',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...state.rules.map(
                              (rule) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: LifeOsSoftCard(
                                  key: Key('automation_rule_card_${rule.id}'),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              rule.nameVi,
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 13.8,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              rule.descriptionVi,
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 12.3,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Switch.adaptive(
                                        key: Key(
                                          'automation_rule_switch_${rule.id}',
                                        ),
                                        value: rule.enabled,
                                        activeTrackColor: c.primary,
                                        onChanged: (val) {
                                          context.read<AutomationBloc>().add(
                                            AutomationRuleToggled(
                                              ruleId: rule.id,
                                              enabled: val,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (state.audits.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(
                                'Nhật ký Thực thi & Hoàn tác',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...state.audits
                                  .take(15)
                                  .map(
                                    (audit) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: LifeOsSoftCard(
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                audit.summaryVi,
                                                softWrap: true,
                                                style: TextStyle(
                                                  fontSize: 12.6,
                                                  color: c.textPrimary,
                                                ),
                                              ),
                                            ),
                                            if (audit.status ==
                                                AutomationAuditStatus.executed)
                                              TextButton(
                                                key: Key(
                                                  'automation_undo_${audit.auditId}',
                                                ),
                                                onPressed: () {
                                                  context
                                                      .read<AutomationBloc>()
                                                      .add(
                                                        AutomationAuditUndoRequested(
                                                          audit.auditId,
                                                        ),
                                                      );
                                                },
                                                child: const Text('Hoàn tác'),
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
      },
    );
  }
}
