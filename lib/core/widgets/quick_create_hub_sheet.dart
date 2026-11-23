import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/app_colors.dart';
import '../../features/authentication/presentation/bloc/auth_bloc.dart';
import '../../features/calendar/presentation/bloc/calendar_bloc.dart';
import '../../features/calendar/presentation/pages/planning_page.dart';
import '../../features/daily_life/domain/entities/daily_life_entities.dart';
import '../../features/daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../features/family/presentation/bloc/family_bloc.dart';
import '../../features/tasks/domain/entities/task_entities.dart';
import '../../features/tasks/domain/repositories/task_repository.dart';
import '../../features/tasks/presentation/bloc/task_bloc.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import '../../features/transactions/presentation/bloc/transaction_bloc.dart';
import '../../features/transactions/presentation/bloc/transaction_event.dart';
import '../utils/smart_quick_entry_parser.dart';
import '../utils/user_behavior_prefs.dart';
import '../utils/vnd_amount.dart';
import 'lifeos_design_system.dart';
import 'voice_smart_capture_sheet.dart';

T? _tryReadBloc<T extends StateStreamableSource<Object?>>(BuildContext context) {
  try {
    return context.read<T>();
  } catch (_) {
    return null;
  }
}

/// Redesigned Center `+` Quick Action Sheet:
/// - Instant 1-line natural input + Voice button at top (saves in 1 tap without leaving page)
/// - 2×3 Bento Grid of crystal-clear everyday actions that open direct mini-forms on the spot
/// - Clean compact footer for bank transaction review & document vault
Future<void> showLifeOsQuickCreateHubSheet(BuildContext context) async {
  final authBloc = _tryReadBloc<AuthBloc>(context);
  final txListBloc = _tryReadBloc<TransactionListBloc>(context);
  final txActionBloc = _tryReadBloc<TransactionActionBloc>(context);
  final calBloc = _tryReadBloc<CalendarBloc>(context);
  final taskBloc = _tryReadBloc<TaskBloc>(context);
  final familyBloc = _tryReadBloc<FamilyBloc>(context);
  final dailyBloc = _tryReadBloc<DailyLifeBloc>(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      return _QuickCreateHubBody(
        parentContext: context,
        authBloc: authBloc,
        txListBloc: txListBloc,
        txActionBloc: txActionBloc,
        calBloc: calBloc,
        taskBloc: taskBloc,
        familyBloc: familyBloc,
        dailyBloc: dailyBloc,
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

  const _QuickCreateHubBody({
    required this.parentContext,
    required this.authBloc,
    required this.txListBloc,
    required this.txActionBloc,
    required this.calBloc,
    required this.taskBloc,
    required this.familyBloc,
    required this.dailyBloc,
  });

  @override
  State<_QuickCreateHubBody> createState() => _QuickCreateHubBodyState();
}

class _QuickCreateHubBodyState extends State<_QuickCreateHubBody> {
  final TextEditingController _quickInputCtrl = TextEditingController();
  ParsedSmartEntry? _parsedDraft;

  @override
  void initState() {
    super.initState();
    UserBehaviorPrefs.loadLastWalletId();
  }

  @override
  void dispose() {
    _quickInputCtrl.dispose();
    super.dispose();
  }

  String _defaultWalletId() {
    final wallets = widget.txListBloc?.state.wallets ?? const <WalletEntity>[];
    return UserBehaviorPrefs.resolvePreferredWalletId(wallets.map((w) => w.id));
  }

  void _saveInlineDraft() {
    final draft = _parsedDraft ?? SmartQuickEntryParser.tryParse(_quickInputCtrl.text);
    final user = widget.authBloc?.state.user;
    final actionBloc = widget.txActionBloc;

    if (draft == null) {
      LifeOsTopToast.show(
        widget.parentContext,
        'Hãy nhập nội dung kèm số tiền, ví dụ: "Ăn sáng 45k" hoặc "Đổ xăng 80k".',
        kind: LifeOsToastKind.warning,
      );
      return;
    }

    if (user == null || actionBloc == null) {
      Navigator.of(context).pop();
      widget.parentContext.go('/finance');
      return;
    }

    final walletId = _defaultWalletId();
    UserBehaviorPrefs.rememberWallet(walletId);
    actionBloc.add(
      TransactionCreateSubmitted(
        operationId: const Uuid().v4(),
        userId: user.id,
        walletId: walletId,
        categoryName: draft.categoryName,
        kind: draft.kind,
        amountMinor: draft.amountMinor,
        merchant: draft.merchant,
        occurredAt: DateTime.now(),
      ),
    );

    Navigator.of(context).pop();
    LifeOsTopToast.show(
      widget.parentContext,
      'Đã lưu: ${draft.merchant} (${VndAmount.format(draft.amountMinor)})',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final pendingBankCount =
        widget.txListBloc?.state.provisionalTransactions.length ?? 0;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    final tiles = <({
      Key key,
      String title,
      String subtitle,
      IconData icon,
      LifeOsAccentTone tone,
      VoidCallback onTap,
    })>[
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
          showVoiceSmartCaptureSheet(widget.parentContext);
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
          final familyId = widget.familyBloc?.state.activeFamily?.id ?? user?.activeFamilyId;
          Navigator.of(context).pop();
          if (user != null && calBloc != null) {
            showDialog<void>(
              context: widget.parentContext,
              builder: (_) => BlocProvider<CalendarBloc>.value(
                value: calBloc,
                child: Builder(
                  builder: (innerCtx) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      Navigator.of(innerCtx).pop();
                      showUpsertCalendarEventDialog(
                        widget.parentContext,
                        userId: user.id,
                        userName: user.fullName,
                        familyId: familyId,
                        availabilityOptIn: user.availabilityOptIn,
                      );
                    });
                    return const SizedBox.shrink();
                  },
                ),
              ),
            );
          } else {
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

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + viewInsets.bottom),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Thêm nhanh',
                        style: TextStyle(
                          fontSize: 18.5,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        'Gõ nhanh một câu hoặc chọn mục bên dưới',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: c.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2. Instant 1-Line Quick Expense Input + Voice Button
            LifeOsMintHeroCard(
              padding: const EdgeInsets.all(12),
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
                            setState(() {
                              _parsedDraft = SmartQuickEntryParser.tryParse(v);
                            });
                          },
                          onSubmitted: (_) => _saveInlineDraft(),
                          decoration: InputDecoration(
                            hintText: 'Gõ nhanh: ăn phở 55k, xăng 80k...',
                            isDense: true,
                            filled: true,
                            fillColor: c.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _saveInlineDraft,
                          child: const Text('Lưu'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_parsedDraft != null)
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 16, color: c.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${_parsedDraft!.kind == TransactionKind.income ? "Thu nhập" : "Chi tiêu"} · '
                            '${_parsedDraft!.merchant} · ${_parsedDraft!.categoryName} · '
                            '${VndAmount.format(_parsedDraft!.amountMinor)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.2,
                              fontWeight: FontWeight.w700,
                              color: c.primary,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final sample in const [
                          'Cà phê 35k',
                          'Ăn trưa 55k',
                          'Đổ xăng 80k',
                        ])
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(sample, style: const TextStyle(fontSize: 11.8)),
                            onPressed: () {
                              setState(() {
                                _quickInputCtrl.text = sample;
                                _quickInputCtrl.selection = TextSelection.collapsed(
                                  offset: sample.length,
                                );
                                _parsedDraft = SmartQuickEntryParser.tryParse(sample);
                              });
                            },
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 3. 2×3 Bento Grid of Everyday Actions (Short, Clear, 1-Tap Direct Sheets)
            for (var i = 0; i < tiles.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 8),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _QuickBentoActionTile(item: tiles[i])),
                    const SizedBox(width: 8),
                    Expanded(child: _QuickBentoActionTile(item: tiles[i + 1])),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),

            // 4. Compact Footer Row: Bank Transaction Review + Document Vault
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('quick_hub_auto_tx_btn'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.parentContext.push('/auto-tx-review');
                      },
                      icon: Icon(Icons.bolt_rounded, size: 17, color: c.primary),
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.parentContext.push('/family-documents');
                      },
                      icon: Icon(Icons.folder_open_rounded, size: 17, color: c.textSecondary),
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
  }) item;

  const _QuickBentoActionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return LifeOsSoftCard(
      key: item.key,
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      onTap: item.onTap,
      child: Row(
        children: [
          LifeOsIconSquircle(
            icon: item.icon,
            tone: item.tone,
            size: 38,
            iconSize: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    color: c.textSecondary,
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

/// Direct 3-step Quick Expense / Income Sheet opened right from `+ -> Ghi thu chi`.
Future<void> _showQuickTransactionSheet(
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
  var kind = TransactionKind.expense;
  var selectedCategory = 'Ăn uống';
  var selectedWalletId = UserBehaviorPrefs.resolvePreferredWalletId(
    wallets.map((w) => w.id),
  );
  final amountCtrl = TextEditingController();
  final noteCtrl = TextEditingController();

  const expenseCategories = <String>[
    'Ăn uống',
    'Di chuyển',
    'Mua sắm',
    'Điện nước',
    'Nhà cửa',
    'Sức khỏe',
  ];
  const incomeCategories = <String>[
    'Lương & Thưởng',
    'Kinh doanh',
    'Thu nhập khác',
  ];

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (ctx, setModal) {
          final c = TammySemanticColors.of(ctx);
          final cats = kind == TransactionKind.expense ? expenseCategories : incomeCategories;
          if (!cats.contains(selectedCategory)) {
            selectedCategory = cats.first;
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              20 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ghi khoản thu chi',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LifeOsSegmentedPills<TransactionKind>(
                    selected: kind,
                    options: const [
                      (TransactionKind.expense, 'Chi tiêu', Icons.north_east_rounded),
                      (TransactionKind.income, 'Thu nhập', Icons.south_west_rounded),
                    ],
                    onChanged: (v) => setModal(() => kind = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('quick_tx_amount_input'),
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    onChanged: (_) => setModal(() {}),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Số tiền (VND)',
                      hintText: 'Gõ ngắn gọn (VD: 45 -> gợi ý 45.000 ₫)',
                      suffixText: '₫',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (_) {
                      final zeroPads =
                          UserBehaviorPrefs.vndZeroPadSuggestions(amountCtrl.text);
                      if (zeroPads.isNotEmpty) {
                        return Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final sug in zeroPads)
                              ActionChip(
                                key: Key('vnd_zero_pad_${sug.$1}'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: c.primarySubtle,
                                side: BorderSide(color: c.primary.withValues(alpha: 0.45)),
                                label: Text(
                                  sug.$2,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: c.primary,
                                  ),
                                ),
                                onPressed: () => setModal(() {
                                  amountCtrl.text = '${sug.$1}';
                                  amountCtrl.selection = TextSelection.collapsed(
                                    offset: amountCtrl.text.length,
                                  );
                                }),
                              ),
                          ],
                        );
                      }
                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final preset in const [
                            (35000, '35.000'),
                            (50000, '50.000'),
                            (100000, '100.000'),
                            (200000, '200.000'),
                            (500000, '500.000'),
                          ])
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              label: Text('${preset.$2} ₫'),
                              onPressed: () => setModal(() {
                                amountCtrl.text = '${preset.$1}';
                                amountCtrl.selection = TextSelection.collapsed(
                                  offset: amountCtrl.text.length,
                                );
                              }),
                            ),
                        ],
                      );
                    },
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
                        label: Text(cat),
                        selected: selectedCategory == cat,
                        onSelected: (_) => setModal(() => selectedCategory = cat),
                      );
                    }).toList(),
                  ),
                  if (wallets.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedWalletId,
                      decoration: const InputDecoration(
                        labelText: 'Chọn ví thanh toán',
                        isDense: true,
                      ),
                      items: wallets
                          .map(
                            (w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(
                                '${w.name} (${VndAmount.format(w.balanceMinor)})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setModal(() => selectedWalletId = v);
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('quick_tx_note_input'),
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú (không bắt buộc)',
                      hintText: 'VD: Ăn trưa văn phòng / Tiền điện',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LifeOsPrimaryCtaButton(
                    icon: Icons.check_rounded,
                    label: 'Lưu khoản này',
                    onPressed: () {
                      final amt = VndAmount.tryParseInput(amountCtrl.text) ?? 0;
                      if (amt <= 0) {
                        LifeOsTopToast.show(
                          context,
                          'Vui lòng nhập số tiền lớn hơn 0 ₫.',
                          kind: LifeOsToastKind.warning,
                        );
                        return;
                      }
                      final merchant = noteCtrl.text.trim().isEmpty
                          ? selectedCategory
                          : noteCtrl.text.trim();
                      UserBehaviorPrefs.rememberWallet(selectedWalletId);
                      txActionBloc.add(
                        TransactionCreateSubmitted(
                          operationId: const Uuid().v4(),
                          userId: user.id,
                          walletId: selectedWalletId,
                          categoryName: selectedCategory,
                          kind: kind,
                          amountMinor: amt,
                          merchant: merchant,
                          occurredAt: DateTime.now(),
                        ),
                      );
                      Navigator.of(sheetCtx).pop();
                      LifeOsTopToast.show(
                        context,
                        'Đã lưu: $merchant (${VndAmount.format(amt)})',
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  amountCtrl.dispose();
  noteCtrl.dispose();
}

/// Direct Quick Task Sheet opened right from `+ -> Thêm việc làm`.
Future<void> _showQuickTaskSheet(
  BuildContext context, {
  required AuthBloc? authBloc,
  required TaskBloc? taskBloc,
  required FamilyBloc? familyBloc,
}) async {
  final user = authBloc?.state.user;
  if (user == null || taskBloc == null) {
    context.push('/tasks-board');
    return;
  }

  final family = familyBloc?.state.activeFamily;
  final members = family?.members ?? const [];
  final titleCtrl = TextEditingController();
  var dueChoice = 'today'; // 'today' | 'tomorrow' | 'weekend'
  var assigneeId = user.id;
  var assigneeName = user.fullName;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (ctx, setModal) {
          final c = TammySemanticColors.of(ctx);
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              20 + MediaQuery.viewInsetsOf(ctx).bottom,
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
                    controller: titleCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Tên công việc',
                      hintText: 'VD: Đóng tiền điện / Mua sữa / Gửi báo cáo',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final preset in const [
                        'Đóng tiền điện nước',
                        'Đi siêu thị mua đồ',
                        'Dọn dẹp nhà cửa',
                      ])
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(preset),
                          onPressed: () => setModal(() => titleCtrl.text = preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Thời hạn hoàn thành',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  LifeOsSegmentedPills<String>(
                    selected: dueChoice,
                    options: const [
                      ('today', 'Hôm nay', null),
                      ('tomorrow', 'Ngày mai', null),
                      ('week', 'Trong tuần', null),
                    ],
                    onChanged: (v) => setModal(() => dueChoice = v),
                  ),
                  if (members.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: assigneeId,
                      decoration: const InputDecoration(
                        labelText: 'Người thực hiện',
                        isDense: true,
                      ),
                      items: members
                          .map<DropdownMenuItem<String>>(
                            (m) => DropdownMenuItem(
                              value: m.userId,
                              child: Text(
                                m.userId == user.id ? '${m.fullName} (Tôi)' : m.fullName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          final found = members.where((m) => m.userId == v).first;
                          setModal(() {
                            assigneeId = v;
                            assigneeName = found.fullName;
                          });
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  LifeOsPrimaryCtaButton(
                    icon: Icons.check_rounded,
                    label: 'Lưu công việc',
                    onPressed: () {
                      final clean = titleCtrl.text.trim();
                      if (clean.length < 2) {
                        LifeOsTopToast.show(
                          context,
                          'Hãy nhập tên công việc cần làm.',
                          kind: LifeOsToastKind.warning,
                        );
                        return;
                      }
                      final now = DateTime.now();
                      final dueAt = switch (dueChoice) {
                        'tomorrow' => DateTime(now.year, now.month, now.day + 1, 18, 0),
                        'week' => DateTime(now.year, now.month, now.day + 3, 18, 0),
                        _ => DateTime(now.year, now.month, now.day, 20, 0),
                      };
                      taskBloc.add(
                        TaskCreateSubmitted(
                          CreateTaskParams(
                            createdBy: user.id,
                            creatorName: user.fullName,
                            familyId: family?.id ?? user.activeFamilyId,
                            assigneeId: assigneeId,
                            assigneeName: assigneeName,
                            title: clean,
                            dueAt: dueAt,
                            recurrence: TaskRecurrence.none,
                          ),
                        ),
                      );
                      Navigator.of(sheetCtx).pop();
                      LifeOsTopToast.show(context, 'Đã thêm việc: "$clean"');
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  titleCtrl.dispose();
}

/// Direct Quick Grocery & Note Sheet opened right from `+ -> Đi chợ & Ghi chú`.
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

  var mode = 'grocery'; // 'grocery' | 'note'
  final titleCtrl = TextEditingController();
  final detailCtrl = TextEditingController();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (ctx, setModal) {
          final c = TammySemanticColors.of(ctx);
          final isGrocery = mode == 'grocery';
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              20 + MediaQuery.viewInsetsOf(ctx).bottom,
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
                    selected: mode,
                    options: const [
                      ('grocery', 'Giỏ đi chợ', Icons.shopping_cart_outlined),
                      ('note', 'Ghi chú nhanh', Icons.sticky_note_2_outlined),
                    ],
                    onChanged: (v) => setModal(() => mode = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('quick_life_title_input'),
                    controller: titleCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: isGrocery ? 'Tên thực phẩm / đồ dùng' : 'Tiêu đề ghi chú',
                      hintText: isGrocery
                          ? 'VD: Thịt bò, rau cải, sữa tươi...'
                          : 'VD: Mật khẩu Wifi / Ý tưởng mới',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('quick_life_detail_input'),
                    controller: detailCtrl,
                    maxLines: isGrocery ? 1 : 3,
                    keyboardType: isGrocery ? TextInputType.number : TextInputType.multiline,
                    decoration: InputDecoration(
                      labelText: isGrocery
                          ? 'Giá dự kiến (không bắt buộc)'
                          : 'Nội dung chi tiết',
                      hintText: isGrocery ? 'VD: 85000' : 'Nhập nội dung cần lưu...',
                      suffixText: isGrocery ? '₫' : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LifeOsPrimaryCtaButton(
                    icon: Icons.check_rounded,
                    label: isGrocery ? 'Thêm vào giỏ đi chợ' : 'Lưu ghi chú',
                    onPressed: () {
                      final cleanTitle = titleCtrl.text.trim();
                      if (cleanTitle.isEmpty) {
                        LifeOsTopToast.show(
                          context,
                          isGrocery
                              ? 'Hãy nhập tên món cần mua.'
                              : 'Hãy nhập tiêu đề ghi chú.',
                          kind: LifeOsToastKind.warning,
                        );
                        return;
                      }
                      if (isGrocery) {
                        final est = VndAmount.tryParseInput(detailCtrl.text) ?? 0;
                        dailyBloc.add(
                          GroceryItemAdded(
                            userId: user.id,
                            name: cleanTitle,
                            quantityLabel: '1 phần',
                            aisle: GroceryAisle.produce,
                            estimatedMinor: est,
                          ),
                        );
                        Navigator.of(sheetCtx).pop();
                        LifeOsTopToast.show(
                          context,
                          'Đã thêm "$cleanTitle" vào giỏ đi chợ.',
                        );
                      } else {
                        dailyBloc.add(
                          SmartNoteSaved(
                            userId: user.id,
                            title: cleanTitle,
                            content: detailCtrl.text.trim(),
                            categoryTag: 'Cá nhân',
                          ),
                        );
                        Navigator.of(sheetCtx).pop();
                        LifeOsTopToast.show(
                          context,
                          'Đã lưu ghi chú "$cleanTitle".',
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  titleCtrl.dispose();
  detailCtrl.dispose();
}
