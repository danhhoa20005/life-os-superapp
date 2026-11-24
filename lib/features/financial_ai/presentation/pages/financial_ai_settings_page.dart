import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/financial_ai_entities.dart';
import '../../domain/entities/gemini_copilot_entities.dart';
import '../bloc/financial_ai_bloc.dart';
import '../bloc/gemini_copilot_bloc.dart';

/// Phase 16.3 & Gemini Connector — AI Learning Settings, Personalization Rule Manager & Opt-in Gemini AI Studio.
class FinancialAiSettingsPage extends StatelessWidget {
  const FinancialAiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EnsureGeminiCopilotScope(child: _FinancialAiSettingsView());
  }
}

class _FinancialAiSettingsView extends StatelessWidget {
  const _FinancialAiSettingsView();

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dateFmt = DateFormat('dd/MM/yyyy');

    return MultiBlocListener(
      listeners: [
        BlocListener<FinancialAiBloc, FinancialAiState>(
          listenWhen: (p, n) =>
              p.failure != n.failure || p.feedbackMessage != n.feedbackMessage,
          listener: (context, state) {
            if (state.failure != null) {
              LifeOsTopToast.show(
                context,
                state.failure!.message,
                kind: LifeOsToastKind.error,
              );
            } else if (state.feedbackMessage != null &&
                state.feedbackMessage!.isNotEmpty) {
              LifeOsTopToast.show(context, state.feedbackMessage!);
            }
          },
        ),
        BlocListener<GeminiCopilotBloc, GeminiCopilotState>(
          listenWhen: (p, n) =>
              p.failure != n.failure || p.feedbackMessage != n.feedbackMessage,
          listener: (context, gState) {
            if (gState.failure != null) {
              LifeOsTopToast.show(
                context,
                gState.failure!.message,
                kind: LifeOsToastKind.error,
              );
            } else if (gState.feedbackMessage != null &&
                gState.feedbackMessage!.isNotEmpty) {
              LifeOsTopToast.show(context, gState.feedbackMessage!);
            }
          },
        ),
      ],
      child: Scaffold(
        body: LifeOsMintWaveCanvas(
          child: SafeArea(
            child: Column(
              children: [
                const LifeOsTopBrandHeader(
                  title: 'Cài đặt AI & Liên kết Gemini',
                  showBackButton: true,
                ),
                Expanded(
                  child: BlocBuilder<FinancialAiBloc, FinancialAiState>(
                    builder: (context, state) {
                      final prefs =
                          state.preferences ??
                          UserAiClassificationPreferences(userId: user.id);
                      final meta = state.modelMetadata;
                      final rules = state.personalizationRules;

                      void updatePrefs(
                        UserAiClassificationPreferences nextPrefs,
                      ) {
                        context.read<FinancialAiBloc>().add(
                          FinancialAiPreferencesUpdated(nextPrefs),
                        );
                      }

                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppSpacing.maxContentWidth,
                          ),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              6,
                              AppSpacing.md,
                              AppSpacing.xxl,
                            ),
                            children: [
                              // 1. Opt-in Gemini AI Connector Studio Card (Top Priority)
                              const _GeminiConnectionStudioCard(),
                              const SizedBox(height: 14),

                              // 2. Offline On-Device Model Information Card
                              LifeOsMintHeroCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.memory_rounded,
                                          color: c.primary,
                                          size: 22,
                                        ),
                                        Text(
                                          'Mô hình AI Trên Thiết bị',
                                          style: TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                        const LifeOsStatusPill(
                                          icon: Icons.lock_outline_rounded,
                                          label: 'Offline · Luôn sẵn sàng',
                                          tone: LifeOsAccentTone.emerald,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Xử lý trực tiếp trên điện thoại · ${meta.numClasses} nhóm ngữ nghĩa tiếng Việt (v${meta.modelVersion})',
                                      softWrap: true,
                                      style: TextStyle(
                                        fontSize: 12.6,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              // 3. AI Classification & Confirmation Policy Switches
                              const LifeOsSectionHeader(
                                title: 'Chế độ Phân loại & Xác nhận',
                              ),
                              const SizedBox(height: 6),
                              LifeOsSoftCard(
                                child: Column(
                                  children: [
                                    SwitchListTile(
                                      key: const Key('toggle_ai_enabled'),
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Bật phân loại AI thông minh',
                                      ),
                                      subtitle: const Text(
                                        'Khi tắt, ứng dụng chỉ dùng bộ từ khóa cố định cơ bản',
                                      ),
                                      value: prefs.aiClassificationEnabled,
                                      onChanged: (v) => updatePrefs(
                                        prefs.copyWith(
                                          aiClassificationEnabled: v,
                                        ),
                                      ),
                                    ),
                                    const Divider(height: 12),
                                    SwitchListTile(
                                      key: const Key(
                                        'toggle_personalization_enabled',
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Học cá nhân hóa theo cửa hàng',
                                      ),
                                      subtitle: const Text(
                                        'Tự ghi nhớ khi bạn đổi danh mục (riêng tư cho từng tài khoản)',
                                      ),
                                      value: prefs.personalizationEnabled,
                                      onChanged: (v) => updatePrefs(
                                        prefs.copyWith(
                                          personalizationEnabled: v,
                                        ),
                                      ),
                                    ),
                                    const Divider(height: 12),
                                    SwitchListTile(
                                      key: const Key(
                                        'toggle_bank_auto_classify',
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Tự động gợi ý danh mục cho thông báo ngân hàng',
                                      ),
                                      subtitle: const Text(
                                        'Áp dụng cho nguồn thông báo ngân hàng đã được bạn cấp quyền',
                                      ),
                                      value:
                                          prefs.autoClassifyBankNotifications,
                                      onChanged: (v) => updatePrefs(
                                        prefs.copyWith(
                                          autoClassifyBankNotifications: v,
                                        ),
                                      ),
                                    ),
                                    const Divider(height: 12),
                                    SwitchListTile(
                                      key: const Key(
                                        'toggle_require_confirm_before_save',
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Luôn yêu cầu xác nhận trước khi ghi sổ',
                                      ),
                                      subtitle: const Text(
                                        'Khuyến nghị bật để đảm bảo an toàn tuyệt đối cho số dư ví',
                                      ),
                                      value:
                                          prefs.requireConfirmationBeforeSave,
                                      onChanged: (v) => updatePrefs(
                                        prefs.copyWith(
                                          requireConfirmationBeforeSave: v,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 4. Learned Personalization Rules List
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Text(
                                    'Quy tắc đã học từ bạn (${rules.length})',
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  if (rules.isNotEmpty)
                                    TextButton.icon(
                                      key: const Key('clear_all_ai_rules_btn'),
                                      onPressed: () =>
                                          _confirmClearAll(context, user.id),
                                      icon: const Icon(
                                        Icons.delete_sweep_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Xóa tất cả quy tắc'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (rules.isEmpty)
                                LifeOsSoftCard(
                                  child: Text(
                                    'Chưa có quy tắc cá nhân hóa nào. Khi bạn sửa danh mục của một cửa hàng (ví dụ: sửa "Circle K" từ Mua sắm sang Ăn uống), hệ thống sẽ lưu quy tắc tại đây.',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 12.8,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                )
                              else
                                ...rules.map(
                                  (rule) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: LifeOsSoftCard(
                                      child: Row(
                                        children: [
                                          const LifeOsIconSquircle(
                                            icon: Icons.psychology_rounded,
                                            tone: LifeOsAccentTone.emerald,
                                            size: 40,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${rule.merchantDisplay} → ${rule.selectedCategoryName}',
                                                  softWrap: true,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  'Đã xác nhận ${rule.confirmationCount} lần · Cập nhật ${dateFmt.format(rule.lastCorrectedAt)}',
                                                  softWrap: true,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            key: Key(
                                              'delete_ai_rule_${rule.id}',
                                            ),
                                            tooltip: 'Xóa quy tắc này',
                                            onPressed: () => context
                                                .read<FinancialAiBloc>()
                                                .add(
                                                  FinancialPersonalizationRuleDeleted(
                                                    userId: user.id,
                                                    ruleId: rule.id,
                                                  ),
                                                ),
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              color: c.textSecondary,
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
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClearAll(BuildContext context, String userId) async {
    final bloc = context.read<FinancialAiBloc>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa dữ liệu cá nhân hóa AI?'),
        content: const Text(
          'Toàn bộ quy tắc gợi ý danh mục theo cửa hàng đã học trên tài khoản này sẽ bị xóa. Các giao dịch lịch sử trong sổ cái hoàn toàn không bị ảnh hưởng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('confirm_clear_all_ai_rules_dialog_btn'),
            onPressed: () {
              bloc.add(FinancialPersonalizationCleared(userId));
              Navigator.of(ctx).pop();
            },
            child: const Text('Xóa dữ liệu học'),
          ),
        ],
      ),
    );
  }
}

class _GeminiConnectionStudioCard extends StatefulWidget {
  const _GeminiConnectionStudioCard();

  @override
  State<_GeminiConnectionStudioCard> createState() =>
      _GeminiConnectionStudioCardState();
}

class _GeminiConnectionStudioCardState
    extends State<_GeminiConnectionStudioCard> {
  final TextEditingController _apiKeyCtrl = TextEditingController();
  bool _obscureKey = true;

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final timeFmt = DateFormat('HH:mm dd/MM');

    return BlocBuilder<GeminiCopilotBloc, GeminiCopilotState>(
      builder: (context, gState) {
        final cfg = gState.config;
        final isVerifying =
            gState.status == GeminiCopilotStatus.verifyingConnection;
        final bloc = context.read<GeminiCopilotBloc>();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LifeOsSectionHeader(
              title: 'Liên kết Gemini AI (Tùy chọn Mở rộng)',
              tone: LifeOsAccentTone.blue,
            ),
            const SizedBox(height: 6),
            LifeOsSoftCard(
              key: const Key('gemini_connection_studio_card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 20,
                            color: cfg.isReadyForCloud
                                ? c.primary
                                : c.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Trợ lý Đa tác vụ Gemini',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      LifeOsStatusPill(
                        icon: cfg.isReadyForCloud
                            ? Icons.check_circle_outline_rounded
                            : Icons.offline_bolt_outlined,
                        label: cfg.isReadyForCloud
                            ? 'Đã nối Gemini'
                            : 'Chạy 100% Trên máy',
                        tone: cfg.isReadyForCloud
                            ? LifeOsAccentTone.emerald
                            : LifeOsAccentTone.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Bóc tách câu ghép đa tác vụ (Thu chi · Lịch hẹn · Việc làm · Đi chợ) và cố vấn chi tiêu thông minh.',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12.4,
                      height: 1.35,
                      color: c.textSecondary,
                    ),
                  ),
                  if (cfg.hasApiKey) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const Key('toggle_gemini_enabled'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bật chế độ kết hợp Gemini AI'),
                      subtitle: Text(
                        cfg.lastVerifiedAt != null
                            ? 'Đã lưu khóa kết nối · Kiểm tra lúc ${timeFmt.format(cfg.lastVerifiedAt!)}'
                            : 'Đã lưu khóa kết nối trên thiết bị',
                      ),
                      value: cfg.enabled,
                      onChanged: (v) => bloc.add(
                        GeminiConnectionSettingsSaved(enabled: v),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('gemini_api_key_input'),
                    controller: _apiKeyCtrl,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: 'Mã Gemini',
                      hintText: 'Dán mã kết nối',
                      hintMaxLines: 2,
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: _obscureKey ? 'Hiện mã' : 'Ẩn mã',
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: const Key('gemini_model_dropdown'),
                    isExpanded: true,
                    initialValue: GeminiModelPreset.fromId(cfg.modelId).modelId,
                    decoration: const InputDecoration(
                      labelText: 'Phiên bản Gemini',
                      isDense: true,
                    ),
                    items: GeminiModelPreset.values
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.modelId,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(m.labelVi),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        bloc.add(GeminiConnectionSettingsSaved(modelId: val));
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    key: const Key('toggle_gemini_mask_pii'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Ẩn số điện thoại, email & số tài khoản',
                    ),
                    subtitle: const Text(
                      'Tự động che thông tin định danh cá nhân trước khi phân tích',
                    ),
                    value: cfg.maskSensitiveInfo,
                    onChanged: (v) => bloc.add(
                      GeminiConnectionSettingsSaved(maskSensitiveInfo: v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const Key('btn_verify_gemini_connection'),
                        onPressed: isVerifying
                            ? null
                            : () {
                                final typed = _apiKeyCtrl.text.trim();
                                bloc.add(
                                  GeminiConnectionTestRequested(
                                    candidateApiKey: typed.isEmpty
                                        ? null
                                        : typed,
                                    modelId: cfg.modelId,
                                  ),
                                );
                                if (typed.isNotEmpty) {
                                  _apiKeyCtrl.clear();
                                }
                              },
                        icon: isVerifying
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.bolt_rounded, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            isVerifying
                                ? 'Đang kiểm tra...'
                                : 'Lưu & Kiểm tra kết nối',
                          ),
                        ),
                      ),
                      if (cfg.hasApiKey)
                        OutlinedButton.icon(
                          key: const Key('btn_disconnect_gemini'),
                          onPressed: isVerifying
                              ? null
                              : () {
                                  _apiKeyCtrl.clear();
                                  bloc.add(
                                    const GeminiConnectionDisconnected(),
                                  );
                                },
                          icon: const Icon(Icons.link_off_rounded, size: 17),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Ngắt liên kết'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
