import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/app_colors.dart';
import '../../features/authentication/domain/entities/user_entity.dart';
import '../../features/authentication/presentation/bloc/auth_bloc.dart';
import '../../features/budgets/presentation/bloc/budget_bloc.dart';
import '../../features/calendar/domain/entities/calendar_entities.dart';
import '../../features/calendar/domain/repositories/calendar_repository.dart';
import '../../features/calendar/presentation/bloc/calendar_bloc.dart';
import '../../features/calendar/presentation/pages/planning_page.dart';
import '../../features/daily_life/domain/entities/daily_life_entities.dart';
import '../../features/daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../features/family/domain/entities/family_entities.dart';
import '../../features/family/domain/usecases/family_usecases.dart';
import '../../features/family/presentation/bloc/family_bloc.dart';
import '../../features/financial_ai/presentation/bloc/gemini_copilot_bloc.dart';
import '../../features/tasks/domain/entities/task_entities.dart';
import '../../features/tasks/domain/repositories/task_repository.dart';
import '../../features/tasks/presentation/bloc/task_bloc.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import '../../features/transactions/presentation/bloc/transaction_bloc.dart';
import '../../features/transactions/presentation/bloc/transaction_event.dart';
import '../../features/transactions/presentation/bloc/transaction_state.dart';
import '../../features/vehicles/presentation/bloc/vehicle_bloc.dart';
import '../di/dependency_injection.dart';
import '../drafts/local_draft_store.dart';
import '../utils/omni_action_executor.dart';
import '../utils/smart_omni_intent_parser.dart';
import '../utils/user_behavior_prefs.dart';
import '../utils/vnd_amount.dart';
import 'lifeos_design_system.dart';
import 'smart_form_inputs.dart';
import 'voice_smart_capture_sheet.dart';

T? _tryReadBloc<T extends StateStreamableSource<Object?>>(
  BuildContext context,
) {
  try {
    return context.read<T>();
  } catch (_) {
    return null;
  }
}

/// Redesigned Center `+` Unified 3-Mode Quick Action Hub:
/// 1. Natural Language Multi-Intent Bar with account-scoped draft persistence & confirmation
/// 2. Voice Smart Capture (`VoiceSmartCaptureSheet`)
/// 3. Direct Quick Action Bento Grid covering all 10 core quick actions + smart forms
Future<void> showLifeOsQuickCreateHubSheet(BuildContext context) async {
  final authBloc = _tryReadBloc<AuthBloc>(context);
  final txListBloc = _tryReadBloc<TransactionListBloc>(context);
  final txActionBloc = _tryReadBloc<TransactionActionBloc>(context);
  final calBloc = _tryReadBloc<CalendarBloc>(context);
  final taskBloc = _tryReadBloc<TaskBloc>(context);
  final familyBloc = _tryReadBloc<FamilyBloc>(context);
  final dailyBloc = _tryReadBloc<DailyLifeBloc>(context);
  final geminiBloc = _tryReadBloc<GeminiCopilotBloc>(context);
  final budgetBloc = _tryReadBloc<BudgetBloc>(context);
  final vehicleBloc = _tryReadBloc<VehicleBloc>(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (sheetCtx) {
      return LiquidGlassSheetFrame(
        showHandle: true,
        child: _QuickCreateHubBody(
          parentContext: context,
          authBloc: authBloc,
          txListBloc: txListBloc,
          txActionBloc: txActionBloc,
          calBloc: calBloc,
          taskBloc: taskBloc,
          familyBloc: familyBloc,
          dailyBloc: dailyBloc,
          geminiBloc: geminiBloc,
          budgetBloc: budgetBloc,
          vehicleBloc: vehicleBloc,
        ),
      );
    },
  );
}

class _QuickCreateHubBody extends StatefulWidget {
  final BuildContext parentContext;
  final AuthBloc? authBloc;
  final TransactionListBloc? txListBloc;
  final TransactionActionBloc? txActionBloc;
  final CalendarBloc? calBloc;
  final TaskBloc? taskBloc;
  final FamilyBloc? familyBloc;
  final DailyLifeBloc? dailyBloc;
  final GeminiCopilotBloc? geminiBloc;
  final BudgetBloc? budgetBloc;
  final VehicleBloc? vehicleBloc;

  const _QuickCreateHubBody({
    required this.parentContext,
    required this.authBloc,
    required this.txListBloc,
    required this.txActionBloc,
    required this.calBloc,
    required this.taskBloc,
    required this.familyBloc,
    required this.dailyBloc,
    required this.geminiBloc,
    required this.budgetBloc,
    required this.vehicleBloc,
  });

  @override
  State<_QuickCreateHubBody> createState() => _QuickCreateHubBodyState();
}

class _QuickCreateHubBodyState extends State<_QuickCreateHubBody>
    with WidgetsBindingObserver {
  static const String _omniDraftFormId = 'quick_hub_omni';

  final TextEditingController _quickInputCtrl = TextEditingController();
  List<OmniActionDraft> _omniDrafts = const <OmniActionDraft>[];
  final Set<String> _excludedDraftIds = <String>{};
  bool _isSubmittingInline = false;

  String? get _activeUserId => widget.authBloc?.state.user?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrateHabitsAndDraft();
  }

  Future<void> _hydrateHabitsAndDraft() async {
    await UserBehaviorPrefs.loadLastWalletId();
    await UserBehaviorPrefs.loadHabitShortcuts();
    final uid = _activeUserId;
    if (uid != null && uid.isNotEmpty) {
      final saved = await LocalDraftStore.loadDraft(
        userId: uid,
        formId: _omniDraftFormId,
      );
      final savedText = (saved?['text'] as String?) ?? '';
      if (mounted &&
          savedText.trim().isNotEmpty &&
          _quickInputCtrl.text.isEmpty) {
        _quickInputCtrl.text = savedText;
        _quickInputCtrl.selection = TextSelection.collapsed(
          offset: savedText.length,
        );
        _omniDrafts = SmartOmniIntentParser.parseMulti(savedText);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _persistOmniDraft(_quickInputCtrl.text);
    }
  }

  void _persistOmniDraft(String rawText) {
    final uid = _activeUserId;
    if (uid == null || uid.isEmpty) return;
    if (rawText.trim().isEmpty) {
      unawaited(
        LocalDraftStore.clearDraft(userId: uid, formId: _omniDraftFormId),
      );
    } else {
      unawaited(
        LocalDraftStore.saveDraft(
          userId: uid,
          formId: _omniDraftFormId,
          payload: <String, dynamic>{'text': rawText},
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _quickInputCtrl.dispose();
    super.dispose();
  }

  String _defaultWalletId() {
    final wallets = widget.txListBloc?.state.wallets ?? const <WalletEntity>[];
    return UserBehaviorPrefs.resolvePreferredWalletId(wallets.map((w) => w.id));
  }

  String _walletDisplayName(String walletId) {
    final wallets = widget.txListBloc?.state.wallets ?? const <WalletEntity>[];
    for (final w in wallets) {
      if (w.id == walletId) return w.name;
    }
    return 'Ví tiền mặt';
  }

  List<OmniActionDraft> get _activeDrafts => _omniDrafts
      .where((d) => !_excludedDraftIds.contains(d.id))
      .toList(growable: false);

  IconData _iconForOmniKind(OmniActionKind kind) => switch (kind) {
    OmniActionKind.transaction => Icons.account_balance_wallet_outlined,
    OmniActionKind.groupSplit => Icons.groups_outlined,
    OmniActionKind.calendarEvent => Icons.event_available_rounded,
    OmniActionKind.task => Icons.task_alt_rounded,
    OmniActionKind.grocery => Icons.shopping_basket_outlined,
    OmniActionKind.waterLog => Icons.water_drop_outlined,
    OmniActionKind.medication => Icons.medication_outlined,
  };

  Future<void> _saveInlineDraft() async {
    if (_isSubmittingInline) return;
    final raw = _quickInputCtrl.text.trim();
    final parsed = _omniDrafts.isNotEmpty
        ? _omniDrafts
        : SmartOmniIntentParser.parseMulti(raw);
    final drafts = parsed
        .where((d) => !_excludedDraftIds.contains(d.id))
        .toList(growable: false);
    final user = widget.authBloc?.state.user;

    if (drafts.isEmpty) {
      final geminiReady =
          widget.geminiBloc?.state.config.isReadyForCloud ?? false;
      if (raw.isNotEmpty && geminiReady) {
        Navigator.of(context).pop();
        widget.parentContext.push('/financial-ai', extra: raw);
        return;
      }
      LifeOsTopToast.show(
        widget.parentContext,
        'Gõ nhanh thu chi, lịch hẹn hoặc việc làm (VD: "Ăn sáng 45k", "Họp 9h mai").',
        kind: LifeOsToastKind.warning,
      );
      return;
    }

    if (user == null) {
      Navigator.of(context).pop();
      widget.parentContext.go('/finance');
      return;
    }

    setState(() => _isSubmittingInline = true);
    final wallets = widget.txListBloc?.state.wallets ?? const <WalletEntity>[];
    final walletId = _defaultWalletId();
    final isSingle = drafts.length == 1;
    var executedCount = 0;
    final failedTitles = <String>[];

    try {
      for (final d in drafts) {
        final ok = await OmniActionExecutor.executeDraft(
          toastContext: widget.parentContext,
          draft: d,
          user: user,
          walletId: walletId,
          availableWallets: wallets,
          txActionBloc: widget.txActionBloc,
          calBloc: widget.calBloc,
          taskBloc: widget.taskBloc,
          familyBloc: widget.familyBloc,
          dailyBloc: widget.dailyBloc,
          budgetBloc: widget.budgetBloc,
          vehicleBloc: widget.vehicleBloc,
          showSuccessToast: isSingle,
        );
        if (ok) {
          executedCount++;
        } else {
          failedTitles.add(d.title);
        }
      }

      if (failedTitles.isEmpty && executedCount > 0) {
        await LocalDraftStore.clearDraft(
          userId: user.id,
          formId: _omniDraftFormId,
        );
        if (mounted) {
          Navigator.of(context).pop();
        }
        if (!isSingle && widget.parentContext.mounted) {
          LifeOsTopToast.show(
            widget.parentContext,
            'Đã thực thi thông minh $executedCount tác vụ từ một câu lệnh!',
          );
        }
      } else {
        // Keep sheet open and preserve unsaved draft so user never loses input!
        _persistOmniDraft(_quickInputCtrl.text);
        if (executedCount > 0 && widget.parentContext.mounted) {
          LifeOsTopToast.show(
            widget.parentContext,
            'Đã lưu $executedCount/${drafts.length} mục; ${failedTitles.length} mục chưa lưu — nháp vẫn được giữ.',
            kind: LifeOsToastKind.warning,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingInline = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final pendingBankCount =
        widget.txListBloc?.state.provisionalTransactions.length ?? 0;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final activeDrafts = _activeDrafts;
    final financialDrafts = activeDrafts
        .where(
          (d) =>
              (d.kind == OmniActionKind.transaction ||
                  d.kind == OmniActionKind.groupSplit) &&
              d.amountMinor > 0,
        )
        .toList(growable: false);
    final totalFinancialMinor = financialDrafts.fold<int>(
      0,
      (sum, d) => sum + d.amountMinor,
    );
    final defaultWalletName = _walletDisplayName(_defaultWalletId());

    final tiles =
        <
          ({
            Key key,
            String title,
            String subtitle,
            IconData icon,
            LifeOsAccentTone tone,
            VoidCallback onTap,
          })
        >[
          (
            key: const Key('quick_tile_expense'),
            title: 'Ghi thu chi',
            subtitle: 'Chi tiêu · Thu nhập',
            icon: Icons.account_balance_wallet_outlined,
            tone: LifeOsAccentTone.emerald,
            onTap: () {
              Navigator.of(context).pop();
              _showQuickTransactionSheet(
                widget.parentContext,
                authBloc: widget.authBloc,
                txListBloc: widget.txListBloc,
                txActionBloc: widget.txActionBloc,
              );
            },
          ),
          (
            key: const Key('quick_tile_split'),
            title: 'Chia tiền nhóm',
            subtitle: 'Chia đều hóa đơn',
            icon: Icons.groups_outlined,
            tone: LifeOsAccentTone.blue,
            onTap: () {
              Navigator.of(context).pop();
              _showQuickSplitBillSheet(
                widget.parentContext,
                authBloc: widget.authBloc,
                familyBloc: widget.familyBloc,
              );
            },
          ),
          (
            key: const Key('quick_tile_event'),
            title: 'Thêm lịch hẹn',
            subtitle: 'Lưu vào Lịch máy',
            icon: Icons.event_available_rounded,
            tone: LifeOsAccentTone.emerald,
            onTap: () {
              final user = widget.authBloc?.state.user;
              final calBloc = widget.calBloc;
              final familyId =
                  widget.familyBloc?.state.activeFamily?.id ??
                  user?.activeFamilyId;
              Navigator.of(context).pop();
              if (user != null &&
                  calBloc != null &&
                  widget.parentContext.mounted) {
                showUpsertCalendarEventDialog(
                  widget.parentContext,
                  userId: user.id,
                  userName: user.fullName,
                  familyId: familyId,
                  availabilityOptIn: user.availabilityOptIn,
                );
              } else if (widget.parentContext.mounted) {
                widget.parentContext.go('/planning');
              }
            },
          ),
          (
            key: const Key('quick_tile_task'),
            title: 'Thêm việc làm',
            subtitle: 'Nhắc việc cần làm',
            icon: Icons.task_alt_rounded,
            tone: LifeOsAccentTone.purple,
            onTap: () {
              Navigator.of(context).pop();
              _showQuickTaskSheet(
                widget.parentContext,
                authBloc: widget.authBloc,
                taskBloc: widget.taskBloc,
                familyBloc: widget.familyBloc,
              );
            },
          ),
          (
            key: const Key('quick_tile_qr'),
            title: 'Mã QR thu tiền',
            subtitle: 'Tạo VietQR nhận tiền',
            icon: Icons.qr_code_2_rounded,
            tone: LifeOsAccentTone.emerald,
            onTap: () {
              Navigator.of(context).pop();
              widget.parentContext.push('/notifications-privacy');
            },
          ),
          (
            key: const Key('quick_tile_note_grocery'),
            title: 'Đi chợ & Ghi chú',
            subtitle: 'Món cần mua · Sổ tay',
            icon: Icons.shopping_basket_outlined,
            tone: LifeOsAccentTone.amber,
            onTap: () {
              Navigator.of(context).pop();
              _showQuickGroceryAndNoteSheet(
                widget.parentContext,
                authBloc: widget.authBloc,
                dailyBloc: widget.dailyBloc,
              );
            },
          ),
        ];

    final compactExtraActions =
        <({Key key, String label, IconData icon, VoidCallback onTap})>[
          (
            key: const Key('quick_tile_transfer'),
            label: 'Chuyển ví',
            icon: Icons.swap_horiz_rounded,
            onTap: () {
              Navigator.of(context).pop();
              _showQuickTransferSheet(
                widget.parentContext,
                authBloc: widget.authBloc,
                txListBloc: widget.txListBloc,
                txActionBloc: widget.txActionBloc,
              );
            },
          ),
          (
            key: const Key('quick_tile_reminder'),
            label: 'Thêm nhắc nhở',
            icon: Icons.notifications_active_outlined,
            onTap: () {
              Navigator.of(context).pop();
              _showQuickReminderSheet(
                widget.parentContext,
                authBloc: widget.authBloc,
                taskBloc: widget.taskBloc,
                calBloc: widget.calBloc,
              );
            },
          ),
          (
            key: const Key('quick_tile_vehicle_expense'),
            label: 'Chi phí xe',
            icon: Icons.two_wheeler_rounded,
            onTap: () {
              Navigator.of(context).pop();
              _showQuickTransactionSheet(
                widget.parentContext,
                authBloc: widget.authBloc,
                txListBloc: widget.txListBloc,
                txActionBloc: widget.txActionBloc,
                initialCategory: 'Xe cộ',
                sheetTitle: 'Ghi chi phí xe',
              );
            },
          ),
        ];

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Clean Header
            Row(
              children: [
                const LifeOsLeafMark(size: 32, borderRadius: 10),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Thêm nhanh',
                    style: TextStyle(
                      fontSize: 18.5,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: c.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 2. Mode 1 + Mode 2: Natural Language Multi-Intent Bar + Voice Button
            LifeOsMintHeroCard(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('quick_hub_smart_input'),
                          controller: _quickInputCtrl,
                          textInputAction: TextInputAction.done,
                          onChanged: (v) {
                            _persistOmniDraft(v);
                            setState(() {
                              _omniDrafts = SmartOmniIntentParser.parseMulti(v);
                              _excludedDraftIds.clear();
                            });
                          },
                          onSubmitted: (_) => _saveInlineDraft(),
                          decoration: InputDecoration(
                            hintText: 'VD: phở 55k',
                            hintMaxLines: 2,
                            isDense: true,
                            filled: true,
                            fillColor: c.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            suffixIcon: _quickInputCtrl.text.isEmpty
                                ? null
                                : IconButton(
                                    key: const Key('quick_hub_clear_input_btn'),
                                    tooltip: 'Xóa nội dung',
                                    constraints: const BoxConstraints(
                                      minWidth: 48,
                                      minHeight: 48,
                                    ),
                                    onPressed: () {
                                      _persistOmniDraft('');
                                      setState(() {
                                        _quickInputCtrl.clear();
                                        _omniDrafts = const [];
                                        _excludedDraftIds.clear();
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 17,
                                    ),
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: c.separator),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: c.separator),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_quickInputCtrl.text.trim().isEmpty)
                        FilledButton.icon(
                          key: const Key('quick_hub_voice_btn'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            showVoiceSmartCaptureSheet(
                              widget.parentContext,
                              autoStartListening: true,
                            );
                          },
                          icon: const Icon(Icons.mic_rounded, size: 18),
                          label: const Text('Nói'),
                        )
                      else
                        FilledButton(
                          key: const Key('quick_hub_save_inline_btn'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _isSubmittingInline
                              ? null
                              : _saveInlineDraft,
                          child: _isSubmittingInline
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Lưu'),
                        ),
                    ],
                  ),
                  if (_omniDrafts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final draft in _omniDrafts)
                      Builder(
                        builder: (_) {
                          final isIncluded = !_excludedDraftIds.contains(
                            draft.id,
                          );
                          return Container(
                            key: Key('quick_hub_draft_card_${draft.id}'),
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isIncluded
                                  ? c.surface
                                  : c.surfaceRaised.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isIncluded
                                    ? c.primary.withValues(alpha: 0.35)
                                    : c.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _iconForOmniKind(draft.kind),
                                  size: 16,
                                  color: isIncluded
                                      ? c.primary
                                      : c.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    draft.summaryLineVi,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 12.2,
                                      fontWeight: FontWeight.w700,
                                      color: isIncluded
                                          ? c.primary
                                          : c.textSecondary,
                                      decoration: isIncluded
                                          ? null
                                          : TextDecoration.lineThrough,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: Key(
                                    'quick_hub_toggle_draft_${draft.id}',
                                  ),
                                  tooltip: isIncluded
                                      ? 'Bỏ tác vụ này'
                                      : 'Khôi phục tác vụ này',
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      if (isIncluded) {
                                        _excludedDraftIds.add(draft.id);
                                      } else {
                                        _excludedDraftIds.remove(draft.id);
                                      }
                                    });
                                  },
                                  icon: Icon(
                                    isIncluded
                                        ? Icons.close_rounded
                                        : Icons.add_circle_outline_rounded,
                                    size: 18,
                                    color: isIncluded
                                        ? c.textSecondary
                                        : c.primary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    if (financialDrafts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          financialDrafts.length >= 2
                              ? 'Xác nhận tài chính (${financialDrafts.length} khoản): ${VndAmount.format(totalFinancialMinor)} · Ví: $defaultWalletName'
                              : 'Ví sẽ ghi: $defaultWalletName · Nhấn Lưu để xác nhận',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ] else if (_quickInputCtrl.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      key: const Key('quick_hub_manual_fallback_box'),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chưa nhận diện được cấu trúc câu lệnh. Bạn có thể chọn nhập thủ công nhanh:',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 12.2,
                              color: c.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                key: const Key('quick_hub_fallback_tx_btn'),
                                onPressed: () {
                                  final noteSeed = _quickInputCtrl.text.trim();
                                  Navigator.of(context).pop();
                                  _showQuickTransactionSheet(
                                    widget.parentContext,
                                    authBloc: widget.authBloc,
                                    txListBloc: widget.txListBloc,
                                    txActionBloc: widget.txActionBloc,
                                    initialNote: noteSeed,
                                  );
                                },
                                icon: const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 16,
                                ),
                                label: const Text('Nhập Thu/Chi thủ công'),
                              ),
                              OutlinedButton.icon(
                                key: const Key('quick_hub_fallback_task_btn'),
                                onPressed: () {
                                  final titleSeed = _quickInputCtrl.text.trim();
                                  Navigator.of(context).pop();
                                  _showQuickTaskSheet(
                                    widget.parentContext,
                                    authBloc: widget.authBloc,
                                    taskBloc: widget.taskBloc,
                                    familyBloc: widget.familyBloc,
                                    initialTitle: titleSeed,
                                  );
                                },
                                icon: const Icon(
                                  Icons.task_alt_rounded,
                                  size: 16,
                                ),
                                label: const Text('Lưu thành việc làm'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 3. Mode 3: Complete Quick Action Bento Grid + Compact Action Pills
            const LifeOsSectionHeader(
              title: 'Tạo mới theo mục',
              padding: EdgeInsets.only(top: 8, bottom: 5, left: 2, right: 2),
            ),
            for (var i = 0; i < tiles.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 6),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _QuickBentoActionTile(item: tiles[i])),
                    const SizedBox(width: 8),
                    Expanded(
                      child: i + 1 < tiles.length
                          ? _QuickBentoActionTile(item: tiles[i + 1])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final act in compactExtraActions)
                  Material(
                    color: c.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: c.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: act.key,
                      onTap: act.onTap,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 48,
                          minWidth: 48,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(act.icon, size: 17, color: c.primary),
                              const SizedBox(width: 6),
                              Text(
                                act.label,
                                style: TextStyle(
                                  fontSize: 12.8,
                                  fontWeight: FontWeight.w700,
                                  color: c.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // 4. Clearly Separated Section: Đối soát & Lưu trữ
            const LifeOsSectionHeader(
              title: 'Đối soát & Lưu trữ',
              tone: LifeOsAccentTone.blue,
              padding: EdgeInsets.only(top: 8, bottom: 5, left: 2, right: 2),
            ),
            OutlinedButton.icon(
              key: const Key('quick_hub_financial_ai_btn'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                final draftText = _quickInputCtrl.text.trim();
                Navigator.of(context).pop();
                widget.parentContext.push(
                  '/financial-ai',
                  extra: draftText.isEmpty ? null : draftText,
                );
              },
              icon: Icon(Icons.edit_note_rounded, size: 18, color: c.primary),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  (widget.geminiBloc?.state.config.isReadyForCloud ?? false)
                      ? 'Nhập gộp nhiều việc & Gemini'
                      : 'Nhập gộp nhiều khoản & lịch hẹn',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('quick_hub_auto_tx_btn'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.parentContext.push('/auto-tx-review');
                      },
                      icon: Icon(
                        Icons.bolt_rounded,
                        size: 17,
                        color: c.primary,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          pendingBankCount > 0
                              ? 'Giao dịch mới ($pendingBankCount)'
                              : 'Duyệt GD tự động',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('quick_hub_doc_btn'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.parentContext.push('/family-documents');
                      },
                      icon: Icon(
                        Icons.folder_open_rounded,
                        size: 17,
                        color: c.textSecondary,
                      ),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Lưu giấy tờ',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('quick_hub_water_med_btn'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _showQuickWaterAndMedSheet(
                  widget.parentContext,
                  authBloc: widget.authBloc,
                  dailyBloc: widget.dailyBloc,
                );
              },
              icon: const Icon(
                Icons.water_drop_outlined,
                size: 17,
                color: Color(0xFF0284C7),
              ),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Nhắc uống nước & Uống thuốc',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickBentoActionTile extends StatelessWidget {
  final ({
    Key key,
    String title,
    String subtitle,
    IconData icon,
    LifeOsAccentTone tone,
    VoidCallback onTap,
  })
  item;

  const _QuickBentoActionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return LifeOsSoftCard(
      key: item.key,
      borderRadius: 16,
      padding: const EdgeInsets.all(10),
      onTap: item.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              LifeOsIconSquircle(
                icon: item.icon,
                tone: item.tone,
                size: 32,
                iconSize: 17,
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: c.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                softWrap: true,
                style: TextStyle(
                  fontSize: 13.2,
                  height: 1.18,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                softWrap: true,
                style: TextStyle(
                  fontSize: 11.2,
                  height: 1.18,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Direct 3-step Quick Expense / Income Sheet opened from `+ -> Ghi thu chi` / `Chi phí xe`.
Future<void> _showQuickTransactionSheet(
  BuildContext context, {
  required AuthBloc? authBloc,
  required TransactionListBloc? txListBloc,
  required TransactionActionBloc? txActionBloc,
  String? initialCategory,
  String? initialNote,
  String? sheetTitle,
}) async {
  final user = authBloc?.state.user;
  if (user == null || txActionBloc == null) {
    context.go('/finance');
    return;
  }

  final wallets = txListBloc?.state.wallets ?? const <WalletEntity>[];
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _QuickTransactionModal(
      parentContext: context,
      userId: user.id,
      wallets: wallets,
      txActionBloc: txActionBloc,
      initialCategory: initialCategory,
      initialNote: initialNote,
      sheetTitle: sheetTitle,
    ),
  );
}

class _QuickTransactionModal extends StatefulWidget {
  final BuildContext parentContext;
  final String userId;
  final List<WalletEntity> wallets;
  final TransactionActionBloc txActionBloc;
  final String? initialCategory;
  final String? initialNote;
  final String? sheetTitle;

  const _QuickTransactionModal({
    required this.parentContext,
    required this.userId,
    required this.wallets,
    required this.txActionBloc,
    this.initialCategory,
    this.initialNote,
    this.sheetTitle,
  });

  @override
  State<_QuickTransactionModal> createState() => _QuickTransactionModalState();
}

class _QuickTransactionModalState extends State<_QuickTransactionModal>
    with WidgetsBindingObserver {
  static const List<String> _expenseCategories = <String>[
    'Ăn uống',
    'Xe cộ',
    'Di chuyển',
    'Mua sắm',
    'Điện nước',
    'Nhà cửa',
    'Sức khỏe',
  ];
  static const List<String> _incomeCategories = <String>[
    'Lương & Thưởng',
    'Kinh doanh',
    'Thu nhập khác',
  ];

  final TextEditingController _amountCtrl = TextEditingController();
  late final TextEditingController _noteCtrl;
  final String _operationId = const Uuid().v4();

  TransactionKind _kind = TransactionKind.expense;
  late String _selectedCategory;
  late String _selectedWalletId;
  bool _isSubmitting = false;

  String get _formId => widget.initialCategory == 'Xe cộ'
      ? 'quick_tx_vehicle_form'
      : 'quick_tx_form';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _noteCtrl = TextEditingController(text: widget.initialNote ?? '');
    _selectedCategory = widget.initialCategory ?? _expenseCategories.first;
    _selectedWalletId = UserBehaviorPrefs.resolvePreferredWalletId(
      widget.wallets.map((w) => w.id),
    );
    _hydrateDraft();
  }

  Future<void> _hydrateDraft() async {
    final draft = await LocalDraftStore.loadDraft(
      userId: widget.userId,
      formId: _formId,
    );
    if (!mounted || draft == null) return;
    setState(() {
      final kindRaw = draft['kind'] as String?;
      if (kindRaw == TransactionKind.income.name) {
        _kind = TransactionKind.income;
      } else if (kindRaw == TransactionKind.expense.name) {
        _kind = TransactionKind.expense;
      }
      final savedCat = draft['category'] as String?;
      final cats = _kind == TransactionKind.expense
          ? _expenseCategories
          : _incomeCategories;
      if (widget.initialCategory == null &&
          savedCat != null &&
          cats.contains(savedCat)) {
        _selectedCategory = savedCat;
      }
      final savedWallet = draft['walletId'] as String?;
      if (savedWallet != null &&
          widget.wallets.any((w) => w.id == savedWallet)) {
        _selectedWalletId = savedWallet;
      }
      final savedAmount = (draft['amountText'] as String?) ?? '';
      if (_amountCtrl.text.isEmpty && savedAmount.isNotEmpty) {
        _amountCtrl.text = savedAmount;
      }
      final savedNote = (draft['noteText'] as String?) ?? '';
      if (_noteCtrl.text.isEmpty && savedNote.isNotEmpty) {
        _noteCtrl.text = savedNote;
      }
    });
  }

  void _saveDraftNow() {
    final hasData =
        _amountCtrl.text.trim().isNotEmpty || _noteCtrl.text.trim().isNotEmpty;
    if (!hasData) {
      unawaited(
        LocalDraftStore.clearDraft(userId: widget.userId, formId: _formId),
      );
      return;
    }
    unawaited(
      LocalDraftStore.saveDraft(
        userId: widget.userId,
        formId: _formId,
        payload: <String, dynamic>{
          'kind': _kind.name,
          'category': _selectedCategory,
          'walletId': _selectedWalletId,
          'amountText': _amountCtrl.text,
          'noteText': _noteCtrl.text,
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveDraftNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final amt = SmartVndAmountParser.tryParse(_amountCtrl.text) ?? 0;
    if (amt <= 0) {
      LifeOsTopToast.show(
        widget.parentContext,
        'Vui lòng nhập số tiền hợp lệ lớn hơn 0 ₫.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    _saveDraftNow();

    final merchant = _noteCtrl.text.trim().isEmpty
        ? _selectedCategory
        : _noteCtrl.text.trim();
    final event = TransactionCreateSubmitted(
      operationId: _operationId,
      userId: widget.userId,
      walletId: _selectedWalletId,
      categoryName: _selectedCategory,
      kind: _kind,
      amountMinor: amt,
      merchant: merchant,
      occurredAt: DateTime.now(),
    );

    final outcome = await widget.txActionBloc.submitAndAwaitCreate(
      event,
      timeout: const Duration(seconds: 6),
    );

    if (outcome.status != ActionStatus.success) {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
      if (widget.parentContext.mounted) {
        LifeOsTopToast.show(
          widget.parentContext,
          outcome.failure?.message ??
              'Không thể lưu giao dịch — dữ liệu nháp vẫn được giữ an toàn.',
          kind: LifeOsToastKind.error,
        );
      }
      return;
    }

    final createdTxId = outcome.lastCreatedTransaction?.id ?? _operationId;
    await LocalDraftStore.clearDraft(userId: widget.userId, formId: _formId);
    await UserBehaviorPrefs.rememberWallet(_selectedWalletId);
    await UserBehaviorPrefs.recordHabitExecution(
      label: '$merchant ${(amt / 1000).round()}k',
      commandText: '$merchant ${(amt / 1000).round()}k',
      categoryName: _selectedCategory,
      amountMinor: amt,
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
    if (widget.parentContext.mounted) {
      LifeOsTopToast.show(
        widget.parentContext,
        'Đã lưu: $merchant (${VndAmount.format(amt)})',
        actionLabel: 'Hoàn tác',
        onAction: () {
          widget.txActionBloc.add(
            TransactionReverseRequested(
              userId: widget.userId,
              transactionId: createdTxId,
              reason: 'Hoàn tác thao tác ghi nhanh',
            ),
          );
          if (widget.parentContext.mounted) {
            LifeOsTopToast.show(
              widget.parentContext,
              'Đã hoàn tác khoản "$merchant".',
              kind: LifeOsToastKind.info,
            );
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final cats = _kind == TransactionKind.expense
        ? _expenseCategories
        : _incomeCategories;
    if (!cats.contains(_selectedCategory)) {
      _selectedCategory = cats.first;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.sheetTitle ?? 'Ghi khoản thu chi',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            LifeOsSegmentedPills<TransactionKind>(
              selected: _kind,
              options: const [
                (TransactionKind.expense, 'Chi tiêu', Icons.north_east_rounded),
                (TransactionKind.income, 'Thu nhập', Icons.south_west_rounded),
              ],
              onChanged: (v) {
                setState(() => _kind = v);
                _saveDraftNow();
              },
            ),
            const SizedBox(height: 12),
            LifeOsVndSmartAmountField(
              fieldKey: const Key('quick_tx_amount_input'),
              controller: _amountCtrl,
              autofocus: true,
              onTextChanged: (_) => _saveDraftNow(),
              onSubmitted: _submit,
            ),
            const SizedBox(height: 12),
            Text(
              'Danh mục',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: cats.map((cat) {
                return ChoiceChip(
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  label: Text(cat),
                  selected: _selectedCategory == cat,
                  onSelected: (_) {
                    setState(() => _selectedCategory = cat);
                    _saveDraftNow();
                  },
                );
              }).toList(),
            ),
            if (widget.wallets.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _selectedWalletId,
                decoration: const InputDecoration(
                  labelText: 'Chọn ví thanh toán',
                  isDense: true,
                ),
                items: widget.wallets
                    .map(
                      (w) => DropdownMenuItem(
                        value: w.id,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${w.name} (${VndAmount.format(w.balanceMinor)})',
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedWalletId = v);
                    _saveDraftNow();
                  }
                },
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              key: const Key('quick_tx_note_input'),
              controller: _noteCtrl,
              onChanged: (_) => _saveDraftNow(),
              decoration: InputDecoration(
                labelText: 'Ghi chú (không bắt buộc)',
                hintText: widget.initialCategory == 'Xe cộ'
                    ? 'VD: Đổ xăng A95 / Thay nhớt xe'
                    : 'VD: Ăn trưa văn phòng / Tiền điện',
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            LifeOsPrimaryCtaButton(
              key: const Key('quick_tx_submit_btn'),
              icon: Icons.check_rounded,
              label: _isSubmitting ? 'Đang lưu...' : 'Lưu khoản này',
              onPressed: _isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Direct Quick Internal Wallet Transfer Sheet (`+ -> Chuyển ví`).
Future<void> _showQuickTransferSheet(
  BuildContext context, {
  required AuthBloc? authBloc,
  required TransactionListBloc? txListBloc,
  required TransactionActionBloc? txActionBloc,
}) async {
  final user = authBloc?.state.user;
  if (user == null || txActionBloc == null) {
    context.go('/finance');
    return;
  }
  final wallets = txListBloc?.state.wallets ?? const <WalletEntity>[];
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _QuickTransferModal(
      parentContext: context,
      userId: user.id,
      wallets: wallets,
      txActionBloc: txActionBloc,
    ),
  );
}

class _QuickTransferModal extends StatefulWidget {
  final BuildContext parentContext;
  final String userId;
  final List<WalletEntity> wallets;
  final TransactionActionBloc txActionBloc;

  const _QuickTransferModal({
    required this.parentContext,
    required this.userId,
    required this.wallets,
    required this.txActionBloc,
  });

  @override
  State<_QuickTransferModal> createState() => _QuickTransferModalState();
}

class _QuickTransferModalState extends State<_QuickTransferModal>
    with WidgetsBindingObserver {
  static const String _formId = 'quick_transfer_form';
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final String _operationId = const Uuid().v4();

  late String _sourceWalletId;
  String? _targetWalletId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sourceWalletId = UserBehaviorPrefs.resolvePreferredWalletId(
      widget.wallets.map((w) => w.id),
    );
    _targetWalletId = widget.wallets.length > 1
        ? widget.wallets
              .firstWhere(
                (w) => w.id != _sourceWalletId,
                orElse: () => widget.wallets.first,
              )
              .id
        : null;
    _hydrateDraft();
  }

  Future<void> _hydrateDraft() async {
    final draft = await LocalDraftStore.loadDraft(
      userId: widget.userId,
      formId: _formId,
    );
    if (!mounted || draft == null) return;
    setState(() {
      final src = draft['sourceWalletId'] as String?;
      if (src != null && widget.wallets.any((w) => w.id == src)) {
        _sourceWalletId = src;
      }
      final dst = draft['targetWalletId'] as String?;
      if (dst != null &&
          dst != _sourceWalletId &&
          widget.wallets.any((w) => w.id == dst)) {
        _targetWalletId = dst;
      }
      final amtText = (draft['amountText'] as String?) ?? '';
      if (_amountCtrl.text.isEmpty && amtText.isNotEmpty) {
        _amountCtrl.text = amtText;
      }
      final noteText = (draft['noteText'] as String?) ?? '';
      if (_noteCtrl.text.isEmpty && noteText.isNotEmpty) {
        _noteCtrl.text = noteText;
      }
    });
  }

  void _saveDraftNow() {
    final hasData =
        _amountCtrl.text.trim().isNotEmpty || _noteCtrl.text.trim().isNotEmpty;
    if (!hasData) {
      unawaited(
        LocalDraftStore.clearDraft(userId: widget.userId, formId: _formId),
      );
      return;
    }
    unawaited(
      LocalDraftStore.saveDraft(
        userId: widget.userId,
        formId: _formId,
        payload: <String, dynamic>{
          'sourceWalletId': _sourceWalletId,
          'targetWalletId': _targetWalletId,
          'amountText': _amountCtrl.text,
          'noteText': _noteCtrl.text,
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveDraftNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (widget.wallets.length < 2 ||
        _targetWalletId == null ||
        _targetWalletId == _sourceWalletId) {
      LifeOsTopToast.show(
        widget.parentContext,
        'Cần chọn 2 ví khác nhau để thực hiện chuyển ví nội bộ.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }
    final amt = SmartVndAmountParser.tryParse(_amountCtrl.text) ?? 0;
    if (amt <= 0) {
      LifeOsTopToast.show(
        widget.parentContext,
        'Vui lòng nhập số tiền chuyển lớn hơn 0 ₫.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    _saveDraftNow();

    final srcName = widget.wallets
        .firstWhere((w) => w.id == _sourceWalletId)
        .name;
    final dstName = widget.wallets
        .firstWhere((w) => w.id == _targetWalletId)
        .name;
    final cleanNote = _noteCtrl.text.trim();

    final outcome = await widget.txActionBloc.submitAndAwaitCreate(
      TransactionCreateSubmitted(
        operationId: _operationId,
        userId: widget.userId,
        walletId: _sourceWalletId,
        targetWalletId: _targetWalletId,
        categoryId: 'cat_transfer',
        categoryName: 'Chuyển khoản nội bộ',
        kind: TransactionKind.transfer,
        amountMinor: amt,
        merchant: cleanNote.isEmpty ? 'Chuyển $srcName → $dstName' : cleanNote,
        note: cleanNote.isEmpty ? null : cleanNote,
        occurredAt: DateTime.now(),
      ),
      timeout: const Duration(seconds: 6),
    );

    if (outcome.status != ActionStatus.success) {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
      if (widget.parentContext.mounted) {
        LifeOsTopToast.show(
          widget.parentContext,
          outcome.failure?.message ??
              'Không thể chuyển ví — bản nháp vẫn được giữ an toàn.',
          kind: LifeOsToastKind.error,
        );
      }
      return;
    }

    await LocalDraftStore.clearDraft(userId: widget.userId, formId: _formId);
    await UserBehaviorPrefs.rememberWallet(_sourceWalletId);
    if (mounted) {
      Navigator.of(context).pop();
    }
    if (widget.parentContext.mounted) {
      LifeOsTopToast.show(
        widget.parentContext,
        'Đã chuyển ${VndAmount.format(amt)} từ $srcName sang $dstName.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final hasEnoughWallets = widget.wallets.length >= 2;
    final parsedAmt = SmartVndAmountParser.tryParse(_amountCtrl.text) ?? 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Chuyển tiền giữa ví',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            if (!hasEnoughWallets) ...[
              LifeOsSoftCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Bạn cần ít nhất 2 ví (VD: Tiền mặt & Vietcombank) để thực hiện chuyển tiền nội bộ.',
                      softWrap: true,
                      style: TextStyle(color: c.textSecondary, fontSize: 13.5),
                    ),
                    const SizedBox(height: 10),
                    LifeOsPrimaryCtaButton(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Mở Sổ Tài chính để thêm ví',
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.parentContext.go('/finance');
                      },
                    ),
                  ],
                ),
              ),
            ] else ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _sourceWalletId,
                decoration: const InputDecoration(
                  labelText: 'Từ ví nguồn',
                  isDense: true,
                ),
                items: widget.wallets
                    .map(
                      (w) => DropdownMenuItem(
                        value: w.id,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${w.name} (${VndAmount.format(w.balanceMinor)})',
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _sourceWalletId = v;
                    if (_targetWalletId == _sourceWalletId) {
                      _targetWalletId = widget.wallets
                          .firstWhere((w) => w.id != _sourceWalletId)
                          .id;
                    }
                  });
                  _saveDraftNow();
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _targetWalletId,
                decoration: const InputDecoration(
                  labelText: 'Sang ví đích',
                  isDense: true,
                ),
                items: widget.wallets
                    .where((w) => w.id != _sourceWalletId)
                    .map(
                      (w) => DropdownMenuItem(
                        value: w.id,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${w.name} (${VndAmount.format(w.balanceMinor)})',
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _targetWalletId = v);
                  _saveDraftNow();
                },
              ),
              const SizedBox(height: 12),
              LifeOsVndSmartAmountField(
                fieldKey: const Key('quick_transfer_amount_input'),
                controller: _amountCtrl,
                autofocus: true,
                onTextChanged: (_) {
                  setState(() {});
                  _saveDraftNow();
                },
                onSubmitted: _submit,
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('quick_transfer_note_input'),
                controller: _noteCtrl,
                onChanged: (_) => _saveDraftNow(),
                decoration: const InputDecoration(
                  labelText: 'Ghi chú (không bắt buộc)',
                  hintText: 'VD: Rút tiền mặt chi tiêu tuần',
                  isDense: true,
                ),
              ),
              if (parsedAmt > 0 && _targetWalletId != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.primarySubtle,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Xác nhận: Chuyển ${VndAmount.format(parsedAmt)} từ ${widget.wallets.firstWhere((w) => w.id == _sourceWalletId).name} → ${widget.wallets.firstWhere((w) => w.id == _targetWalletId).name}',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: c.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              LifeOsPrimaryCtaButton(
                key: const Key('quick_transfer_submit_btn'),
                icon: Icons.swap_horiz_rounded,
                label: _isSubmitting ? 'Đang chuyển...' : 'Xác nhận chuyển ví',
                onPressed: _isSubmitting ? null : _submit,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Genuine Manual Quick Split Bill Sheet (`+ -> Chia tiền nhóm`) with
/// exact per-person preview AND 1-tap voice capture shortcut inside.
Future<void> _showQuickSplitBillSheet(
  BuildContext context, {
  required AuthBloc? authBloc,
  required FamilyBloc? familyBloc,
}) async {
  final user = authBloc?.state.user;
  if (user == null || familyBloc == null) {
    context.go('/family');
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _QuickSplitBillModal(
      parentContext: context,
      authBloc: authBloc!,
      familyBloc: familyBloc,
    ),
  );
}

class _QuickSplitBillModal extends StatefulWidget {
  final BuildContext parentContext;
  final AuthBloc authBloc;
  final FamilyBloc familyBloc;

  const _QuickSplitBillModal({
    required this.parentContext,
    required this.authBloc,
    required this.familyBloc,
  });

  @override
  State<_QuickSplitBillModal> createState() => _QuickSplitBillModalState();
}

class _QuickSplitBillModalState extends State<_QuickSplitBillModal>
    with WidgetsBindingObserver {
  static const String _formId = 'quick_split_form';
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  int _participantCount = 2;
  bool _isSubmitting = false;

  String get _userId => widget.authBloc.state.user?.id ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final familyMemberCount =
        widget.familyBloc.state.activeFamily?.members.length ?? 2;
    _participantCount = familyMemberCount.clamp(2, 30);
    _hydrateDraft();
  }

  Future<void> _hydrateDraft() async {
    if (_userId.isEmpty) return;
    final draft = await LocalDraftStore.loadDraft(
      userId: _userId,
      formId: _formId,
    );
    if (!mounted || draft == null) return;
    setState(() {
      final savedTitle = (draft['title'] as String?) ?? '';
      if (_titleCtrl.text.isEmpty && savedTitle.isNotEmpty) {
        _titleCtrl.text = savedTitle;
      }
      final savedAmt = (draft['amountText'] as String?) ?? '';
      if (_amountCtrl.text.isEmpty && savedAmt.isNotEmpty) {
        _amountCtrl.text = savedAmt;
      }
      final count = (draft['participantCount'] as num?)?.toInt();
      if (count != null) {
        _participantCount = count.clamp(2, 30);
      }
    });
  }

  void _saveDraftNow() {
    if (_userId.isEmpty) return;
    final hasData =
        _titleCtrl.text.trim().isNotEmpty || _amountCtrl.text.trim().isNotEmpty;
    if (!hasData) {
      unawaited(LocalDraftStore.clearDraft(userId: _userId, formId: _formId));
      return;
    }
    unawaited(
      LocalDraftStore.saveDraft(
        userId: _userId,
        formId: _formId,
        payload: <String, dynamic>{
          'title': _titleCtrl.text,
          'amountText': _amountCtrl.text,
          'participantCount': _participantCount,
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveDraftNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final user = widget.authBloc.state.user;
    if (user == null) return;

    final cleanTitle = _titleCtrl.text.trim().isEmpty
        ? 'Chia hóa đơn nhóm'
        : _titleCtrl.text.trim();
    final totalMinor = SmartVndAmountParser.tryParse(_amountCtrl.text) ?? 0;
    if (totalMinor <= 0) {
      LifeOsTopToast.show(
        widget.parentContext,
        'Vui lòng nhập tổng số tiền hóa đơn hợp lệ.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    _saveDraftNow();

    try {
      var targetFamily = widget.familyBloc.state.activeFamily;
      if (targetFamily == null && sl.isRegistered<CreateFamilyUseCase>()) {
        final createRes = await sl<CreateFamilyUseCase>()(
          CreateFamilyParams(
            userId: user.id,
            userName: user.fullName,
            familyName: 'Nhóm Chia Tiền Nhanh',
            spaceType: CollaborationSpaceType.group,
          ),
        );
        targetFamily = createRes.fold((_) => null, (fam) => fam);
      }

      final famId = targetFamily?.id ?? user.activeFamilyId;
      if (famId == null || famId.isEmpty) {
        if (mounted) setState(() => _isSubmitting = false);
        if (widget.parentContext.mounted) {
          LifeOsTopToast.show(
            widget.parentContext,
            'Chưa có nhóm gia đình/bạn bè — hãy tạo hoặc tham gia nhóm trước.',
            kind: LifeOsToastKind.warning,
          );
        }
        return;
      }

      final participantIds = <String>[user.id];
      final participantNames = <String, String>{user.id: user.fullName};
      final existingOthers =
          (targetFamily?.members ?? const <FamilyMemberInfo>[])
              .where((m) => m.userId != user.id)
              .toList();
      for (var i = 1; i < _participantCount; i++) {
        if (i - 1 < existingOthers.length) {
          final m = existingOthers[i - 1];
          participantIds.add(m.userId);
          participantNames[m.userId] = m.fullName;
        } else {
          final guestId = 'guest_member_$i';
          participantIds.add(guestId);
          participantNames[guestId] = 'Thành viên ${i + 1}';
        }
      }

      final params = CreateSharedBillSplitParams(
        familyId: famId,
        title: cleanTitle,
        topic: SharedExpenseTopic.dining,
        paidByUserId: user.id,
        paidByName: user.fullName,
        totalAmountMinor: totalMinor,
        splitMethod: SplitMethod.equal,
        participantIds: participantIds,
        participantNames: participantNames,
        rawInputValuesByUserId: const <String, int>{},
        choreOrTaskNote: 'Chia nhanh từ Thêm nhanh (+)',
      );

      final waiter = widget.familyBloc.stream
          .firstWhere(
            (s) => !s.isSubmitting && (s.message != null || s.failure != null),
          )
          .timeout(
            const Duration(seconds: 6),
            onTimeout: () => widget.familyBloc.state,
          );
      widget.familyBloc.add(SharedBillSplitCreated(params));
      final famState = await waiter;

      if (famState.failure != null || famState.message == null) {
        if (mounted) setState(() => _isSubmitting = false);
        if (widget.parentContext.mounted) {
          LifeOsTopToast.show(
            widget.parentContext,
            famState.failure?.message ??
                'Không thể lưu khoản chia tiền — nháp vẫn được giữ.',
            kind: LifeOsToastKind.error,
          );
        }
        return;
      }

      await LocalDraftStore.clearDraft(userId: user.id, formId: _formId);
      final perPerson = totalMinor ~/ _participantCount;
      if (mounted) Navigator.of(context).pop();
      if (widget.parentContext.mounted) {
        LifeOsTopToast.show(
          widget.parentContext,
          'Đã chia "$cleanTitle": ${VndAmount.format(perPerson)}/người ($_participantCount người).',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final totalMinor = SmartVndAmountParser.tryParse(_amountCtrl.text) ?? 0;
    final perPerson = totalMinor > 0 ? totalMinor ~/ _participantCount : 0;
    final remainder = totalMinor > 0 ? totalMinor % _participantCount : 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chia tiền nhóm',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const Key('quick_split_voice_btn'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () {
                    Navigator.of(context).pop();
                    showVoiceSmartCaptureSheet(
                      widget.parentContext,
                      autoStartListening: true,
                    );
                  },
                  icon: const Icon(Icons.mic_rounded, size: 18),
                  label: const Text('Nói chia tiền'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('quick_split_title_input'),
              controller: _titleCtrl,
              autofocus: true,
              onChanged: (_) => _saveDraftNow(),
              decoration: const InputDecoration(
                labelText: 'Nội dung khoản chi chung',
                hintText: 'VD: Ăn lẩu, Cafe nhóm, Tiền điện',
              ),
            ),
            const SizedBox(height: 12),
            LifeOsVndSmartAmountField(
              fieldKey: const Key('quick_split_amount_input'),
              controller: _amountCtrl,
              labelText: 'Tổng hóa đơn (VND)',
              onTextChanged: (_) {
                setState(() {});
                _saveDraftNow();
              },
              onSubmitted: _submit,
            ),
            const SizedBox(height: 12),
            Text(
              'Số người tham gia chia đều',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton.outlined(
                  key: const Key('quick_split_dec_btn'),
                  tooltip: 'Giảm số người',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: _participantCount > 2
                      ? () {
                          setState(() => _participantCount--);
                          _saveDraftNow();
                        }
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Text(
                  '$_participantCount người',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton.outlined(
                  key: const Key('quick_split_inc_btn'),
                  tooltip: 'Tăng số người',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: _participantCount < 30
                      ? () {
                          setState(() => _participantCount++);
                          _saveDraftNow();
                        }
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
                for (final preset in const [2, 3, 4, 5])
                  ChoiceChip(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    label: Text('$preset người'),
                    selected: _participantCount == preset,
                    onSelected: (_) {
                      setState(() => _participantCount = preset);
                      _saveDraftNow();
                    },
                  ),
              ],
            ),
            if (totalMinor > 0) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('quick_split_preview_banner'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.primarySubtle,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.primary.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.groups_rounded, size: 19, color: c.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        remainder == 0
                            ? 'Mỗi người góp: ${VndAmount.format(perPerson)} (× $_participantCount người)'
                            : 'Mỗi người góp: ${VndAmount.format(perPerson)} (dư ${VndAmount.format(remainder)} chia vào người trả)',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 13.2,
                          fontWeight: FontWeight.w800,
                          color: c.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            LifeOsPrimaryCtaButton(
              key: const Key('quick_split_submit_btn'),
              icon: Icons.check_rounded,
              label: _isSubmitting ? 'Đang chia...' : 'Lưu chia tiền nhóm',
              onPressed: _isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Direct Quick Task Sheet opened from `+ -> Thêm việc làm`.
Future<void> _showQuickTaskSheet(
  BuildContext context, {
  required AuthBloc? authBloc,
  required TaskBloc? taskBloc,
  required FamilyBloc? familyBloc,
  String? initialTitle,
}) async {
  final user = authBloc?.state.user;
  if (user == null || taskBloc == null) {
    context.push('/tasks-board');
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _QuickTaskModal(
      parentContext: context,
      user: user,
      taskBloc: taskBloc,
      familyBloc: familyBloc,
      initialTitle: initialTitle,
    ),
  );
}

class _QuickTaskModal extends StatefulWidget {
  final BuildContext parentContext;
  final UserEntity user;
  final TaskBloc taskBloc;
  final FamilyBloc? familyBloc;
  final String? initialTitle;

  const _QuickTaskModal({
    required this.parentContext,
    required this.user,
    required this.taskBloc,
    required this.familyBloc,
    this.initialTitle,
  });

  @override
  State<_QuickTaskModal> createState() => _QuickTaskModalState();
}

class _QuickTaskModalState extends State<_QuickTaskModal>
    with WidgetsBindingObserver {
  static const String _formId = 'quick_task_form';
  late final TextEditingController _titleCtrl;
  VietnameseRelativeTimePreset? _selectedPreset =
      VietnameseRelativeTimePreset.today;
  late DateTime _dueAt;
  bool _isAmbiguous = false;
  late String _assigneeId;
  late String _assigneeName;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _titleCtrl = TextEditingController(text: widget.initialTitle ?? '');
    final (dt, _, amb) = VietnameseRelativeTimeResolver.resolve(
      VietnameseRelativeTimePreset.today,
      DateTime.now(),
    );
    _dueAt = dt;
    _isAmbiguous = amb;
    _assigneeId = widget.user.id;
    _assigneeName = widget.user.fullName;
    _hydrateDraft();
  }

  Future<void> _hydrateDraft() async {
    final draft = await LocalDraftStore.loadDraft(
      userId: widget.user.id,
      formId: _formId,
    );
    if (!mounted || draft == null) return;
    setState(() {
      final savedTitle = (draft['title'] as String?) ?? '';
      if (_titleCtrl.text.isEmpty && savedTitle.isNotEmpty) {
        _titleCtrl.text = savedTitle;
      }
      final dueIso = draft['dueAtIso'] as String?;
      final parsedDue = dueIso != null ? DateTime.tryParse(dueIso) : null;
      if (parsedDue != null) {
        _dueAt = parsedDue;
      }
      final presetName = draft['preset'] as String?;
      if (presetName != null) {
        _selectedPreset = VietnameseRelativeTimePreset.values
            .where((p) => p.name == presetName)
            .firstOrNull;
      }
      _isAmbiguous = (draft['isAmbiguous'] as bool?) ?? false;
    });
  }

  void _saveDraftNow() {
    final uid = widget.user.id;
    if (_titleCtrl.text.trim().isEmpty) {
      unawaited(LocalDraftStore.clearDraft(userId: uid, formId: _formId));
      return;
    }
    unawaited(
      LocalDraftStore.saveDraft(
        userId: uid,
        formId: _formId,
        payload: <String, dynamic>{
          'title': _titleCtrl.text,
          'dueAtIso': _dueAt.toIso8601String(),
          'preset': _selectedPreset?.name,
          'isAmbiguous': _isAmbiguous,
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveDraftNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final clean = _titleCtrl.text.trim();
    if (clean.length < 2) {
      LifeOsTopToast.show(
        widget.parentContext,
        'Hãy nhập tên công việc cần làm (tối thiểu 2 ký tự).',
        kind: LifeOsToastKind.warning,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    _saveDraftNow();

    final family = widget.familyBloc?.state.activeFamily;
    final uid = widget.user.id;
    final waiter = widget.taskBloc.stream
        .firstWhere((s) => s.message != null || s.failure != null)
        .timeout(
          const Duration(seconds: 6),
          onTimeout: () => widget.taskBloc.state,
        );
    widget.taskBloc.add(
      TaskCreateSubmitted(
        CreateTaskParams(
          createdBy: uid,
          creatorName: widget.user.fullName,
          familyId: family?.id ?? widget.user.activeFamilyId,
          assigneeId: _assigneeId,
          assigneeName: _assigneeName,
          title: clean,
          dueAt: _dueAt,
          recurrence: TaskRecurrence.none,
        ),
      ),
    );

    final res = await waiter;
    if (res.failure != null || res.message == null) {
      if (mounted) setState(() => _isSubmitting = false);
      if (widget.parentContext.mounted) {
        LifeOsTopToast.show(
          widget.parentContext,
          res.failure?.message ??
              'Không thể lưu công việc — bản nháp vẫn được giữ.',
          kind: LifeOsToastKind.error,
        );
      }
      return;
    }

    await LocalDraftStore.clearDraft(userId: uid, formId: _formId);
    if (mounted) Navigator.of(context).pop();
    if (widget.parentContext.mounted) {
      LifeOsTopToast.show(widget.parentContext, 'Đã thêm việc: "$clean"');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final family = widget.familyBloc?.state.activeFamily;
    final members = family?.members ?? const <FamilyMemberInfo>[];
    final uid = widget.user.id;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Thêm việc cần làm',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('quick_task_title_input'),
              controller: _titleCtrl,
              autofocus: true,
              onChanged: (_) => _saveDraftNow(),
              decoration: const InputDecoration(
                labelText: 'Tên công việc',
                hintText: 'VD: Đóng tiền điện / Mua sữa / Gửi báo cáo',
              ),
            ),
            const SizedBox(height: 12),
            LifeOsRelativeDateTimePicker(
              title: 'Thời hạn hoàn thành',
              selectedDateTime: _dueAt,
              selectedPreset: _selectedPreset,
              isAmbiguous: _isAmbiguous,
              onChanged: (dt, preset, amb) {
                setState(() {
                  _dueAt = dt;
                  _selectedPreset = preset;
                  _isAmbiguous = amb;
                });
                _saveDraftNow();
              },
            ),
            if (members.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _assigneeId,
                decoration: const InputDecoration(
                  labelText: 'Người thực hiện',
                  isDense: true,
                ),
                items: members
                    .map<DropdownMenuItem<String>>(
                      (m) => DropdownMenuItem(
                        value: m.userId,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            m.userId == uid
                                ? '${m.fullName} (Tôi)'
                                : m.fullName,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    final found = members.where((m) => m.userId == v).first;
                    setState(() {
                      _assigneeId = v;
                      _assigneeName = found.fullName;
                    });
                  }
                },
              ),
            ],
            const SizedBox(height: 14),
            LifeOsPrimaryCtaButton(
              key: const Key('quick_task_submit_btn'),
              icon: Icons.check_rounded,
              label: _isSubmitting ? 'Đang lưu...' : 'Lưu công việc',
              onPressed: _isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Direct Quick Reminder Sheet opened from `+ -> Thêm nhắc nhở`.
Future<void> _showQuickReminderSheet(
  BuildContext context, {
  required AuthBloc? authBloc,
  required TaskBloc? taskBloc,
  required CalendarBloc? calBloc,
}) async {
  final user = authBloc?.state.user;
  if (user == null || (taskBloc == null && calBloc == null)) {
    context.go('/planning');
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _QuickReminderModal(
      parentContext: context,
      userId: user.id,
      userName: user.fullName,
      activeFamilyId: user.activeFamilyId,
      taskBloc: taskBloc,
      calBloc: calBloc,
    ),
  );
}

class _QuickReminderModal extends StatefulWidget {
  final BuildContext parentContext;
  final String userId;
  final String userName;
  final String? activeFamilyId;
  final TaskBloc? taskBloc;
  final CalendarBloc? calBloc;

  const _QuickReminderModal({
    required this.parentContext,
    required this.userId,
    required this.userName,
    required this.activeFamilyId,
    required this.taskBloc,
    required this.calBloc,
  });

  @override
  State<_QuickReminderModal> createState() => _QuickReminderModalState();
}

class _QuickReminderModalState extends State<_QuickReminderModal>
    with WidgetsBindingObserver {
  static const String _formId = 'quick_reminder_form';
  final TextEditingController _titleCtrl = TextEditingController();
  VietnameseRelativeTimePreset? _selectedPreset =
      VietnameseRelativeTimePreset.in15Minutes;
  late DateTime _remindAt;
  bool _isAmbiguous = false;
  late String _targetMode; // 'task' | 'calendar'
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _targetMode = widget.calBloc != null ? 'calendar' : 'task';
    final (dt, _, amb) = VietnameseRelativeTimeResolver.resolve(
      VietnameseRelativeTimePreset.in15Minutes,
      DateTime.now(),
    );
    _remindAt = dt;
    _isAmbiguous = amb;
    _hydrateDraft();
  }

  Future<void> _hydrateDraft() async {
    final draft = await LocalDraftStore.loadDraft(
      userId: widget.userId,
      formId: _formId,
    );
    if (!mounted || draft == null) return;
    setState(() {
      final savedTitle = (draft['title'] as String?) ?? '';
      if (_titleCtrl.text.isEmpty && savedTitle.isNotEmpty) {
        _titleCtrl.text = savedTitle;
      }
      final mode = draft['targetMode'] as String?;
      if (mode == 'calendar' && widget.calBloc != null) {
        _targetMode = 'calendar';
      } else if (mode == 'task' && widget.taskBloc != null) {
        _targetMode = 'task';
      }
      final iso = draft['remindAtIso'] as String?;
      final dt = iso != null ? DateTime.tryParse(iso) : null;
      if (dt != null) _remindAt = dt;
      final presetName = draft['preset'] as String?;
      if (presetName != null) {
        _selectedPreset = VietnameseRelativeTimePreset.values
            .where((p) => p.name == presetName)
            .firstOrNull;
      }
      _isAmbiguous = (draft['isAmbiguous'] as bool?) ?? false;
    });
  }

  void _saveDraftNow() {
    if (_titleCtrl.text.trim().isEmpty) {
      unawaited(
        LocalDraftStore.clearDraft(userId: widget.userId, formId: _formId),
      );
      return;
    }
    unawaited(
      LocalDraftStore.saveDraft(
        userId: widget.userId,
        formId: _formId,
        payload: <String, dynamic>{
          'title': _titleCtrl.text,
          'targetMode': _targetMode,
          'remindAtIso': _remindAt.toIso8601String(),
          'preset': _selectedPreset?.name,
          'isAmbiguous': _isAmbiguous,
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveDraftNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final clean = _titleCtrl.text.trim();
    if (clean.length < 2) {
      LifeOsTopToast.show(
        widget.parentContext,
        'Hãy nhập nội dung cần nhắc (tối thiểu 2 ký tự).',
        kind: LifeOsToastKind.warning,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    _saveDraftNow();

    if (_targetMode == 'calendar' && widget.calBloc != null) {
      final calBloc = widget.calBloc!;
      final waiter = calBloc.stream
          .firstWhere((s) => s.message != null || s.failure != null)
          .timeout(const Duration(seconds: 6), onTimeout: () => calBloc.state);
      calBloc.add(
        CalendarEventCreated(
          CreateCalendarEventParams(
            userId: widget.userId,
            userName: widget.userName,
            familyId: widget.activeFamilyId,
            visibility: CalendarEventVisibility.privateEvent,
            title: clean,
            startsAt: _remindAt,
            endsAt: _remindAt.add(const Duration(minutes: 30)),
            reminderMinutesBefore: 15,
          ),
        ),
      );
      final res = await waiter;
      if (res.failure != null || res.message == null) {
        if (mounted) setState(() => _isSubmitting = false);
        if (widget.parentContext.mounted) {
          LifeOsTopToast.show(
            widget.parentContext,
            res.failure?.message ??
                'Không thể đặt nhắc nhở — bản nháp vẫn được giữ.',
            kind: LifeOsToastKind.error,
          );
        }
        return;
      }
    } else if (widget.taskBloc != null) {
      final taskBloc = widget.taskBloc!;
      final waiter = taskBloc.stream
          .firstWhere((s) => s.message != null || s.failure != null)
          .timeout(const Duration(seconds: 6), onTimeout: () => taskBloc.state);
      taskBloc.add(
        TaskCreateSubmitted(
          CreateTaskParams(
            createdBy: widget.userId,
            creatorName: widget.userName,
            familyId: widget.activeFamilyId,
            assigneeId: widget.userId,
            assigneeName: widget.userName,
            title: clean,
            dueAt: _remindAt,
            priority: TaskPriorityLevel.high,
            recurrence: TaskRecurrence.none,
          ),
        ),
      );
      final res = await waiter;
      if (res.failure != null || res.message == null) {
        if (mounted) setState(() => _isSubmitting = false);
        if (widget.parentContext.mounted) {
          LifeOsTopToast.show(
            widget.parentContext,
            res.failure?.message ??
                'Không thể đặt nhắc nhở — bản nháp vẫn được giữ.',
            kind: LifeOsToastKind.error,
          );
        }
        return;
      }
    }

    await LocalDraftStore.clearDraft(userId: widget.userId, formId: _formId);
    if (mounted) Navigator.of(context).pop();
    if (widget.parentContext.mounted) {
      LifeOsTopToast.show(
        widget.parentContext,
        'Đã đặt nhắc nhở: "$clean" (${VietnameseRelativeTimeResolver.formatExplanation(_remindAt)})',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final showBothTargets = widget.calBloc != null && widget.taskBloc != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Thêm nhắc nhở nhanh',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            if (showBothTargets) ...[
              const SizedBox(height: 10),
              LifeOsSegmentedPills<String>(
                selected: _targetMode,
                options: const [
                  ('calendar', 'Lịch nhắc', Icons.event_available_rounded),
                  ('task', 'Nhắc việc', Icons.task_alt_rounded),
                ],
                onChanged: (v) {
                  setState(() => _targetMode = v);
                  _saveDraftNow();
                },
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const Key('quick_reminder_title_input'),
              controller: _titleCtrl,
              autofocus: true,
              onChanged: (_) => _saveDraftNow(),
              decoration: const InputDecoration(
                labelText: 'Nội dung nhắc nhở',
                hintText: 'VD: Gọi khách hàng / Thanh toán tiền nhà',
              ),
            ),
            const SizedBox(height: 12),
            LifeOsRelativeDateTimePicker(
              title: 'Thời điểm nhắc',
              selectedDateTime: _remindAt,
              selectedPreset: _selectedPreset,
              isAmbiguous: _isAmbiguous,
              onChanged: (dt, preset, amb) {
                setState(() {
                  _remindAt = dt;
                  _selectedPreset = preset;
                  _isAmbiguous = amb;
                });
                _saveDraftNow();
              },
            ),
            const SizedBox(height: 14),
            LifeOsPrimaryCtaButton(
              key: const Key('quick_reminder_submit_btn'),
              icon: Icons.notifications_active_outlined,
              label: _isSubmitting ? 'Đang đặt nhắc...' : 'Lưu nhắc nhở',
              onPressed: _isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Direct Quick Grocery & Note Sheet opened from `+ -> Đi chợ & Ghi chú`.
Future<void> _showQuickGroceryAndNoteSheet(
  BuildContext context, {
  required AuthBloc? authBloc,
  required DailyLifeBloc? dailyBloc,
}) async {
  final user = authBloc?.state.user;
  if (user == null || dailyBloc == null) {
    context.push('/kitchen-groceries');
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _QuickGroceryAndNoteModal(
      parentContext: context,
      userId: user.id,
      dailyBloc: dailyBloc,
    ),
  );
}

class _QuickGroceryAndNoteModal extends StatefulWidget {
  final BuildContext parentContext;
  final String userId;
  final DailyLifeBloc dailyBloc;

  const _QuickGroceryAndNoteModal({
    required this.parentContext,
    required this.userId,
    required this.dailyBloc,
  });

  @override
  State<_QuickGroceryAndNoteModal> createState() =>
      _QuickGroceryAndNoteModalState();
}

class _QuickGroceryAndNoteModalState extends State<_QuickGroceryAndNoteModal>
    with WidgetsBindingObserver {
  static const String _formId = 'quick_grocery_note_form';
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _detailCtrl = TextEditingController();
  String _mode = 'grocery'; // 'grocery' | 'note'
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrateDraft();
  }

  Future<void> _hydrateDraft() async {
    final draft = await LocalDraftStore.loadDraft(
      userId: widget.userId,
      formId: _formId,
    );
    if (!mounted || draft == null) return;
    setState(() {
      final mode = draft['mode'] as String?;
      if (mode == 'grocery' || mode == 'note') {
        _mode = mode!;
      }
      final savedTitle = (draft['title'] as String?) ?? '';
      if (_titleCtrl.text.isEmpty && savedTitle.isNotEmpty) {
        _titleCtrl.text = savedTitle;
      }
      final savedDetail = (draft['detail'] as String?) ?? '';
      if (_detailCtrl.text.isEmpty && savedDetail.isNotEmpty) {
        _detailCtrl.text = savedDetail;
      }
    });
  }

  void _saveDraftNow() {
    final hasData =
        _titleCtrl.text.trim().isNotEmpty || _detailCtrl.text.trim().isNotEmpty;
    if (!hasData) {
      unawaited(
        LocalDraftStore.clearDraft(userId: widget.userId, formId: _formId),
      );
      return;
    }
    unawaited(
      LocalDraftStore.saveDraft(
        userId: widget.userId,
        formId: _formId,
        payload: <String, dynamic>{
          'mode': _mode,
          'title': _titleCtrl.text,
          'detail': _detailCtrl.text,
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveDraftNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleCtrl.dispose();
    _detailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final isGrocery = _mode == 'grocery';
    final cleanTitle = _titleCtrl.text.trim();
    if (cleanTitle.isEmpty) {
      LifeOsTopToast.show(
        widget.parentContext,
        isGrocery ? 'Hãy nhập tên món cần mua.' : 'Hãy nhập tiêu đề ghi chú.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    _saveDraftNow();

    final waiter = widget.dailyBloc.stream
        .firstWhere((s) => s.successBanner != null || s.failure != null)
        .timeout(
          const Duration(seconds: 6),
          onTimeout: () => widget.dailyBloc.state,
        );

    if (isGrocery) {
      final est = SmartVndAmountParser.tryParse(_detailCtrl.text) ?? 0;
      widget.dailyBloc.add(
        GroceryItemAdded(
          userId: widget.userId,
          name: cleanTitle,
          quantityLabel: '1 phần',
          aisle: GroceryAisle.produce,
          estimatedMinor: est,
        ),
      );
    } else {
      widget.dailyBloc.add(
        SmartNoteSaved(
          userId: widget.userId,
          title: cleanTitle,
          content: _detailCtrl.text.trim(),
          categoryTag: 'Cá nhân',
        ),
      );
    }

    final res = await waiter;
    if (res.failure != null || res.successBanner == null) {
      if (mounted) setState(() => _isSubmitting = false);
      if (widget.parentContext.mounted) {
        LifeOsTopToast.show(
          widget.parentContext,
          res.failure?.message ??
              'Không thể lưu nội dung — bản nháp vẫn được giữ.',
          kind: LifeOsToastKind.error,
        );
      }
      return;
    }

    await LocalDraftStore.clearDraft(userId: widget.userId, formId: _formId);
    if (mounted) Navigator.of(context).pop();
    if (widget.parentContext.mounted) {
      LifeOsTopToast.show(
        widget.parentContext,
        isGrocery
            ? 'Đã thêm "$cleanTitle" vào giỏ đi chợ.'
            : 'Đã lưu ghi chú "$cleanTitle".',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isGrocery = _mode == 'grocery';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isGrocery ? 'Thêm món cần mua' : 'Viết ghi chú nhanh',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            LifeOsSegmentedPills<String>(
              selected: _mode,
              options: const [
                ('grocery', 'Giỏ đi chợ', Icons.shopping_cart_outlined),
                ('note', 'Ghi chú nhanh', Icons.sticky_note_2_outlined),
              ],
              onChanged: (v) {
                setState(() => _mode = v);
                _saveDraftNow();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('quick_life_title_input'),
              controller: _titleCtrl,
              autofocus: true,
              onChanged: (_) => _saveDraftNow(),
              decoration: InputDecoration(
                labelText: isGrocery
                    ? 'Tên thực phẩm / đồ dùng'
                    : 'Tiêu đề ghi chú',
                hintText: isGrocery
                    ? 'VD: Thịt bò, rau cải, sữa tươi...'
                    : 'VD: Mật khẩu Wifi / Ý tưởng mới',
              ),
            ),
            const SizedBox(height: 10),
            if (isGrocery)
              LifeOsVndSmartAmountField(
                fieldKey: const Key('quick_life_detail_input'),
                controller: _detailCtrl,
                labelText: 'Giá dự kiến (không bắt buộc)',
                hintText: 'VD: 85000, 85k',
                allowEmpty: true,
                onTextChanged: (_) => _saveDraftNow(),
                onSubmitted: _submit,
              )
            else
              TextField(
                key: const Key('quick_life_detail_input'),
                controller: _detailCtrl,
                maxLines: 3,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => _saveDraftNow(),
                decoration: const InputDecoration(
                  labelText: 'Nội dung chi tiết',
                  hintText: 'Nhập nội dung cần lưu...',
                ),
              ),
            const SizedBox(height: 14),
            LifeOsPrimaryCtaButton(
              key: const Key('quick_life_submit_btn'),
              icon: Icons.check_rounded,
              label: _isSubmitting
                  ? 'Đang lưu...'
                  : (isGrocery ? 'Thêm vào giỏ đi chợ' : 'Lưu ghi chú'),
              onPressed: _isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Direct Quick Water & Medication Reminder Sheet opened right from `+ -> Nhắc uống nước & Uống thuốc`.
Future<void> _showQuickWaterAndMedSheet(
  BuildContext context, {
  required AuthBloc? authBloc,
  required DailyLifeBloc? dailyBloc,
}) async {
  final user = authBloc?.state.user;
  if (user == null || dailyBloc == null) {
    context.push('/health-hub');
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => BlocProvider<DailyLifeBloc>.value(
      value: dailyBloc,
      child: _QuickWaterAndMedModal(parentContext: context, userId: user.id),
    ),
  );
}

class _QuickWaterAndMedModal extends StatefulWidget {
  final BuildContext parentContext;
  final String userId;

  const _QuickWaterAndMedModal({
    required this.parentContext,
    required this.userId,
  });

  @override
  State<_QuickWaterAndMedModal> createState() => _QuickWaterAndMedModalState();
}

class _QuickWaterAndMedModalState extends State<_QuickWaterAndMedModal> {
  String _mode = 'water'; // 'water' | 'med'
  final TextEditingController _medNameCtrl = TextEditingController();
  final TextEditingController _medDoseCtrl = TextEditingController(
    text: '1 viên sau ăn',
  );
  MedicationScheduleSlot _slot = MedicationScheduleSlot.morning;
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 30);

  @override
  void dispose() {
    _medNameCtrl.dispose();
    _medDoseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final hyd = context.watch<DailyLifeBloc>().state.snapshot.hydration;
    final bloc = context.read<DailyLifeBloc>();
    final hh = _time.hour.toString().padLeft(2, '0');
    final mm = _time.minute.toString().padLeft(2, '0');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _mode == 'water' ? 'Uống nước & Hẹn nhắc' : 'Đặt nhắc uống thuốc',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            LifeOsSegmentedPills<String>(
              selected: _mode,
              options: const [
                ('water', 'Uống nước', Icons.water_drop_outlined),
                ('med', 'Uống thuốc', Icons.medication_outlined),
              ],
              onChanged: (v) => setState(() => _mode = v),
            ),
            const SizedBox(height: 12),
            if (_mode == 'water') ...[
              Text(
                'Hôm nay: ${hyd.waterMl} / ${hyd.targetWaterMl} ml (${hyd.progressPct}%)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final ml in const [150, 250, 350, 500])
                    FilledButton.tonalIcon(
                      key: Key('quick_sheet_water_$ml'),
                      onPressed: () {
                        bloc.add(
                          WaterIntakeLogged(
                            userId: widget.userId,
                            deltaMl: ml,
                            targetWaterMl: hyd.targetWaterMl,
                          ),
                        );
                        Navigator.of(context).pop();
                        LifeOsTopToast.show(
                          widget.parentContext,
                          'Đã ghi nhận +$ml ml nước uống hôm nay.',
                        );
                      },
                      icon: const Icon(Icons.local_drink_outlined, size: 16),
                      label: Text('+$ml ml'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('quick_sheet_water_reminder_switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Bật nhắc uống nước định kỳ'),
                subtitle: Text(
                  'Nhắc mỗi ${hyd.intervalMinutes} phút (${hyd.startHour.toString().padLeft(2, "0")}:00 – ${hyd.endHour.toString().padLeft(2, "0")}:00)',
                ),
                value: hyd.reminderEnabled,
                onChanged: (val) {
                  bloc.add(
                    HydrationReminderSettingsSaved(
                      userId: widget.userId,
                      reminderEnabled: val,
                      intervalMinutes: hyd.intervalMinutes,
                      startHour: hyd.startHour,
                      endHour: hyd.endHour,
                      targetWaterMl: hyd.targetWaterMl,
                    ),
                  );
                },
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.parentContext.push('/health-hub?tab=water');
                },
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Mở trang Theo dõi Nước & Chu kỳ'),
                ),
              ),
            ] else ...[
              TextField(
                key: const Key('quick_sheet_med_name_input'),
                controller: _medNameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Tên thuốc',
                  hintText: 'VD: Vitamin D3, Thuốc cảm',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _medDoseCtrl,
                decoration: const InputDecoration(labelText: 'Liều dùng'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<MedicationScheduleSlot>(
                isExpanded: true,
                initialValue: _slot,
                decoration: const InputDecoration(labelText: 'Cữ uống'),
                items: MedicationScheduleSlot.values
                    .where((s) => s.isScheduledDaily)
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(s.label),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _slot = v;
                      _time = TimeOfDay(
                        hour: v.defaultHour,
                        minute: v.defaultMinute,
                      );
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _time,
                  );
                  if (picked != null && mounted) {
                    setState(() => _time = picked);
                  }
                },
                icon: const Icon(Icons.alarm_rounded, size: 18),
                label: Text('Giờ chuông nhắc: $hh:$mm'),
              ),
              const SizedBox(height: 12),
              LifeOsPrimaryCtaButton(
                key: const Key('quick_sheet_save_med_btn'),
                icon: Icons.check_rounded,
                label: 'Lưu & Đặt nhắc thuốc',
                onPressed: () {
                  final cleanName = _medNameCtrl.text.trim();
                  if (cleanName.isEmpty) {
                    LifeOsTopToast.show(
                      widget.parentContext,
                      'Vui lòng nhập tên thuốc cần nhắc.',
                      kind: LifeOsToastKind.warning,
                    );
                    return;
                  }
                  bloc.add(
                    MedicationCabinetAdded(
                      userId: widget.userId,
                      name: cleanName,
                      dosage: _medDoseCtrl.text.trim(),
                      slot: _slot,
                      remainingPills: 30,
                      expiryDate: DateTime.now().add(const Duration(days: 270)),
                      reminderEnabled: true,
                      reminderHour: _time.hour,
                      reminderMinute: _time.minute,
                    ),
                  );
                  Navigator.of(context).pop();
                  LifeOsTopToast.show(
                    widget.parentContext,
                    'Đã đặt nhắc uống "$cleanName" lúc $hh:$mm.',
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
