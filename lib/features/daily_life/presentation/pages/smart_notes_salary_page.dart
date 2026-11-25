import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/navigation/feature_registry.dart';
import '../../../../core/utils/privacy_mask_formatter.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vietnamese_search_matcher.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../../transactions/presentation/bloc/transaction_state.dart';
import '../../domain/entities/daily_life_entities.dart';
import '../bloc/daily_life_bloc.dart';

class SmartNotesSalaryPage extends StatefulWidget {
  final String? initialTab;

  const SmartNotesSalaryPage({super.key, this.initialTab});

  @override
  State<SmartNotesSalaryPage> createState() => _SmartNotesSalaryPageState();
}

class _SmartNotesSalaryPageState extends State<SmartNotesSalaryPage> {
  late String _tab;
  final TextEditingController _noteSearchCtrl = TextEditingController();
  String _noteSearch = '';
  bool _pinnedOnly = false;
  final Set<String> _revealedNoteIds = <String>{};
  String? _selectedWalletId;
  bool _isSubmittingSalary = false;

  // Vietnam Gross <-> Net & 5-Bracket 2026 PIT Salary Engine State (Luật 109/2025/QH15)
  bool _grossToNetMode = true;
  int _salaryInputMinor = 25000000;
  int _dependents = 0;
  VietnamTaxPolicy _taxPolicy = VietnamTaxPolicy.law109Year2026;
  VietnamWageRegion _wageRegion = VietnamWageRegion.region1;

  static const List<int> _salaryPresets = [
    15000000,
    25000000,
    35000000,
    50000000,
    80000000,
  ];

  @override
  void initState() {
    super.initState();
    _tab = FeatureRegistry.normalizeSmartNotesSalaryTab(widget.initialTab);
  }

  @override
  void didUpdateWidget(covariant SmartNotesSalaryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _tab = FeatureRegistry.normalizeSmartNotesSalaryTab(widget.initialTab);
    }
  }

  @override
  void dispose() {
    _noteSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final userId = user?.id ?? '';
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    final String? resolvedWalletId = wallets.isEmpty
        ? null
        : (_selectedWalletId != null &&
                  wallets.any((w) => w.id == _selectedWalletId)
              ? _selectedWalletId!
              : UserBehaviorPrefs.resolvePreferredWalletId(
                  wallets.map((w) => w.id),
                ));

    final salaryResult = _grossToNetMode
        ? VietnamGrossNetTaxEngine.fromGross(
            grossMinor: _salaryInputMinor,
            dependentsCount: _dependents,
            policy: _taxPolicy,
            region: _wageRegion,
          )
        : VietnamGrossNetTaxEngine.fromNet(
            targetNetMinor: _salaryInputMinor,
            dependentsCount: _dependents,
            policy: _taxPolicy,
            region: _wageRegion,
          );

    return BlocConsumer<DailyLifeBloc, DailyLifeState>(
      listenWhen: (p, n) =>
          (n.failure != null && p.failure != n.failure) ||
          (n.successBanner != null && p.successBanner != n.successBanner),
      listener: (context, state) {
        if (state.failure != null) {
          LifeOsTopToast.show(
            context,
            state.failure!.message,
            kind: LifeOsToastKind.error,
          );
        } else if (state.successBanner != null) {
          LifeOsTopToast.show(context, state.successBanner!);
        }
      },
      builder: (context, state) {
        final notes = state.snapshot.notes;
        final pinnedCount = notes.where((n) => n.isPinned).length;

        return Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              child: Column(
                children: [
                  const LifeOsTopBrandHeader(
                    title: 'Ghi chú & Lương Gross–Net',
                    showBackButton: true,
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
                            4,
                            AppSpacing.md,
                            AppSpacing.xxl,
                          ),
                          children: [
                            // Hero Card
                            LifeOsMintHeroCard(
                              child: Row(
                                children: [
                                  const LifeOsIconSquircle(
                                    icon: Icons.edit_note_rounded,
                                    tone: LifeOsAccentTone.purple,
                                    size: 44,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Sổ tay Ghi chú & Lương Thực nhận',
                                          style: TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          '${notes.length} ghi chú ($pinnedCount ghim) · Lương Net ước tính: ${VndAmount.format(salaryResult.netSalaryMinor)}',
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 12.2,
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
                            const SizedBox(height: 12),

                            LifeOsSegmentedPills<String>(
                              selected: _tab,
                              onChanged: (v) => setState(() => _tab = v),
                              options: const [
                                (
                                  'notes',
                                  'Sổ tay Ghi chú',
                                  Icons.sticky_note_2_outlined,
                                ),
                                (
                                  'salary',
                                  'Lương Gross ⇄ Net',
                                  Icons.request_quote_outlined,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            if (_tab == 'notes')
                              _buildNotesTab(context, c, userId, notes)
                            else
                              _buildSalaryTaxTab(
                                context,
                                c,
                                userId,
                                wallets,
                                resolvedWalletId,
                                salaryResult,
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
      },
    );
  }

  Widget _buildNotesTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    List<SmartLifeNoteEntity> notes,
  ) {
    final dtFmt = DateFormat('dd/MM HH:mm');
    final pinnedCount = notes.where((n) => n.isPinned).length;
    final hasActiveFilter = _pinnedOnly || _noteSearch.trim().isNotEmpty;
    final filtered = notes.where((n) {
      if (_pinnedOnly && !n.isPinned) return false;
      return VietnameseSearchMatcher.matchesAny(_noteSearch, [
        n.title,
        n.content,
        n.categoryTag,
      ]);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('smart_notes_search_field'),
          controller: _noteSearchCtrl,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Tìm ghi chú',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _noteSearch.isNotEmpty
                ? IconButton(
                    key: const Key('smart_notes_clear_btn'),
                    tooltip: 'Xóa tìm kiếm',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _noteSearchCtrl.clear();
                      setState(() => _noteSearch = '');
                    },
                  )
                : null,
          ),
          onChanged: (v) => setState(() => _noteSearch = v),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ChoiceChip(
              key: const Key('smart_notes_filter_all'),
              label: Text('Tất cả (${notes.length})'),
              selected: !_pinnedOnly && _noteSearch.trim().isEmpty,
              onSelected: (_) {
                _noteSearchCtrl.clear();
                setState(() {
                  _pinnedOnly = false;
                  _noteSearch = '';
                });
              },
            ),
            ChoiceChip(
              key: const Key('smart_notes_filter_pinned'),
              label: Text('Đã ghim ($pinnedCount)'),
              selected: _pinnedOnly,
              onSelected: (sel) => setState(() => _pinnedOnly = sel),
            ),
          ],
        ),
        const SizedBox(height: 10),

        LifeOsPrimaryCtaButton(
          key: const Key('open_add_smart_note_btn'),
          label: '+ Tạo Ghi Chú Mới',
          icon: Icons.note_add_outlined,
          onPressed: userId.isEmpty
              ? null
              : () => _showNoteEditorSheet(context, userId),
        ),
        const SizedBox(height: 12),

        if (filtered.isEmpty)
          LifeOsSoftCard(
            child: Column(
              children: [
                Icon(
                  hasActiveFilter
                      ? Icons.search_off_rounded
                      : Icons.lightbulb_outline_rounded,
                  size: 38,
                  color: c.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  hasActiveFilter
                      ? 'Không tìm thấy ghi chú khớp bộ lọc'
                      : 'Sổ tay Ghi chú đang sẵn sàng',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasActiveFilter
                      ? 'Hãy xóa từ khóa hoặc chuyển về Tất cả để xem toàn bộ ghi chú đã lưu.'
                      : 'Lưu mã số, thông tin quan trọng hoặc checklist ghim đầu trang.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                ),
                if (hasActiveFilter) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    key: const Key('smart_notes_reset_filter_btn'),
                    onPressed: () {
                      _noteSearchCtrl.clear();
                      setState(() {
                        _pinnedOnly = false;
                        _noteSearch = '';
                      });
                    },
                    icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                    label: const Text('Xóa bộ lọc'),
                  ),
                ],
              ],
            ),
          )
        else
          ...filtered.map((note) {
            final isSecret = note.categoryTag == 'Mã số & Wi-Fi';
            final isRevealed = _revealedNoteIds.contains(note.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: LifeOsSoftCard(
                key: Key('smart_note_card_${note.id}'),
                padding: const EdgeInsets.all(14),
                onTap: userId.isEmpty
                    ? null
                    : () => _showNoteEditorSheet(
                        context,
                        userId,
                        existing: note,
                      ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        LifeOsIconSquircle(
                          icon: note.isPinned
                              ? Icons.push_pin_rounded
                              : Icons.description_outlined,
                          tone: note.isPinned
                              ? LifeOsAccentTone.amber
                              : LifeOsAccentTone.purple,
                          size: 38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                note.title,
                                softWrap: true,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                '${note.categoryTag} · ${dtFmt.format(note.updatedAt)}',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 11.8,
                                  color: c.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: Key('pin_smart_note_${note.id}'),
                          visualDensity: VisualDensity.compact,
                          tooltip: note.isPinned ? 'Bỏ ghim' : 'Ghim đầu trang',
                          onPressed: () => context.read<DailyLifeBloc>().add(
                            SmartNotePinToggled(userId: userId, note: note),
                          ),
                          icon: Icon(
                            note.isPinned
                                ? Icons.push_pin_rounded
                                : Icons.push_pin_outlined,
                            size: 19,
                            color: note.isPinned ? c.primary : c.textSecondary,
                          ),
                        ),
                        IconButton(
                          key: Key('delete_smart_note_${note.id}'),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Xóa ghi chú',
                          onPressed: userId.isEmpty
                              ? null
                              : () => _confirmDeleteNote(context, userId, note),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (note.content.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      if (isSecret)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: c.surfaceRaised,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  isRevealed
                                      ? note.content
                                      : PrivacyMaskFormatter.maskNotePreview(
                                          note.content,
                                        ),
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isRevealed
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: isRevealed
                                        ? c.textPrimary
                                        : c.textSecondary,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: Key('toggle_note_reveal_${note.id}'),
                                visualDensity: VisualDensity.compact,
                                tooltip: isRevealed
                                    ? 'Ẩn mã số / Wi-Fi'
                                    : 'Hiện mã số / Wi-Fi',
                                onPressed: () {
                                  setState(() {
                                    if (isRevealed) {
                                      _revealedNoteIds.remove(note.id);
                                    } else {
                                      _revealedNoteIds.add(note.id);
                                    }
                                  });
                                },
                                icon: Icon(
                                  isRevealed
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 19,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          note.content,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 13.2,
                            color: c.textPrimary,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _recordSalaryToWallet({
    required String userId,
    required List<WalletEntity> wallets,
    required String? selectedWalletId,
    required VietnamSalaryTaxResult res,
  }) async {
    if (wallets.isEmpty || selectedWalletId == null) {
      LifeOsTopToast.show(
        context,
        'Vui lòng tạo ít nhất 1 Ví trong tab Tài chính trước khi ghi lương.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }
    if (_isSubmittingSalary || res.netSalaryMinor <= 0) return;

    final txActionBloc = context.read<TransactionActionBloc>();
    setState(() => _isSubmittingSalary = true);
    late final TransactionActionState outcome;
    try {
      outcome = await txActionBloc.submitAndAwaitCreate(
        TransactionCreateSubmitted(
          operationId: 'sal_${DateTime.now().millisecondsSinceEpoch}',
          userId: userId,
          walletId: selectedWalletId,
          categoryId: 'cat_income_salary',
          categoryName: 'Lương & Thu nhập',
          kind: TransactionKind.income,
          amountMinor: res.netSalaryMinor,
          merchant: 'Lương thực nhận (Net)',
          note:
              'Gross ${VndAmount.format(res.grossSalaryMinor)} · Thuế TNCN ${VndAmount.format(res.personalIncomeTaxMinor)}',
          occurredAt: DateTime.now(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingSalary = false);
      }
    }

    if (!mounted) return;
    final createdTx = outcome.lastCreatedTransaction;
    if (outcome.status != ActionStatus.success || createdTx == null) {
      LifeOsTopToast.show(
        context,
        outcome.failure?.message ??
            'Không thể ghi Lương thực nhận vào Ví — vui lòng thử lại.',
        kind: LifeOsToastKind.error,
      );
      return;
    }

    await UserBehaviorPrefs.rememberWallet(selectedWalletId);
    if (!mounted) return;
    final confirmedTxId = createdTx.id;
    LifeOsTopToast.show(
      context,
      'Đã cộng Lương thực nhận (${VndAmount.format(res.netSalaryMinor)}) vào Ví.',
      actionLabel: 'Hoàn tác',
      onAction: () {
        txActionBloc.add(
          TransactionReverseRequested(
            userId: userId,
            transactionId: confirmedTxId,
            reason: 'Hoàn tác ghi nhận lương thực nhận',
          ),
        );
        if (mounted) {
          LifeOsTopToast.show(
            context,
            'Đã hoàn tác khoản Lương thực nhận.',
            kind: LifeOsToastKind.info,
          );
        }
      },
    );
  }

  Future<void> _showExactSalaryDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: '$_salaryInputMinor');
    final parsed = await showDialog<int>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          _grossToNetMode
              ? 'Nhập mức lương Gross chính xác'
              : 'Nhập mức lương Net mong muốn',
        ),
        content: TextField(
          key: const Key('salary_exact_amount_input'),
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          decoration: const InputDecoration(
            labelText: 'Số tiền (VNĐ)',
            hintText: 'VD: 18500000',
            suffixText: '₫',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('confirm_exact_salary_btn'),
            onPressed: () {
              final amt =
                  VndAmount.tryParseInput(ctrl.text) ??
                  int.tryParse(ctrl.text.trim()) ??
                  0;
              if (amt <= 0 || amt > 2000000000) {
                LifeOsTopToast.show(
                  dialogCtx,
                  'Vui lòng nhập mức lương hợp lệ từ 1 ₫ đến 2.000.000.000 ₫.',
                  kind: LifeOsToastKind.warning,
                );
                return;
              }
              Navigator.of(dialogCtx).pop(amt);
            },
            child: const Text('Áp dụng'),
          ),
        ],
      ),
    );
    if (parsed != null && mounted) {
      setState(() => _salaryInputMinor = parsed);
    }
  }

  Widget _buildSalaryTaxTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    List<WalletEntity> wallets,
    String? resolvedWalletId,
    VietnamSalaryTaxResult res,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Chiều quy đổi Lương',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: c.textPrimary,
                    ),
                  ),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Gross → Net'),
                        ),
                      ),
                      ButtonSegment(
                        value: false,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Net → Gross'),
                        ),
                      ),
                    ],
                    selected: {_grossToNetMode},
                    onSelectionChanged: (s) =>
                        setState(() => _grossToNetMode = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _salaryPresets.map((amt) {
                  final active = _salaryInputMinor == amt;
                  return ChoiceChip(
                    label: Text(
                      '${amt ~/ 1000000} triệu',
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    selected: active,
                    onSelected: (_) => setState(() => _salaryInputMinor = amt),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _grossToNetMode
                          ? 'Mức lương Gross đầu vào'
                          : 'Mức lương Net mong muốn',
                      softWrap: true,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Chạm để nhập số tiền lương chính xác',
                    child: Material(
                      color: c.primarySubtle,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        key: const Key('salary_exact_amount_tap'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _showExactSalaryDialog(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                VndAmount.format(_salaryInputMinor),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: c.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.edit_outlined,
                                size: 14,
                                color: c.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value: (_salaryInputMinor / 1000000).clamp(6.0, 150.0),
                min: 6.0,
                max: 150.0,
                divisions: 144,
                onChanged: (v) =>
                    setState(() => _salaryInputMinor = v.round() * 1000000),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Người phụ thuộc (${VndAmount.format(_taxPolicy.dependentDeductionVnd)}/người)',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 13,
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _dependents,
                    underline: const SizedBox.shrink(),
                    items: const [0, 1, 2, 3, 4, 5]
                        .map(
                          (d) => DropdownMenuItem(
                            value: d,
                            child: Text(
                              '$d người',
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _dependents = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<VietnamTaxPolicy>(
                isExpanded: true,
                initialValue: _taxPolicy,
                decoration: const InputDecoration(
                  labelText: 'Chính sách Thuế TNCN & Giảm trừ gia cảnh',
                  isDense: true,
                ),
                items: VietnamTaxPolicy.values
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                          p.title,
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _taxPolicy = v);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<VietnamWageRegion>(
                isExpanded: true,
                initialValue: _wageRegion,
                decoration: const InputDecoration(
                  labelText: 'Vùng lương tối thiểu đóng BHTN (NĐ 293/2025)',
                  isDense: true,
                ),
                items: VietnamWageRegion.values
                    .map(
                      (r) => DropdownMenuItem(value: r, child: Text(r.label)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _wageRegion = v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Detailed Statutory Breakdown
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bảng bóc tách Bảo hiểm bắt buộc & Thuế TNCN',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              _TaxLine(
                label: 'Lương Gross (Trước thuế)',
                amount: res.grossSalaryMinor,
                bold: true,
              ),
              _TaxLine(label: 'Trích BHXH (8%)', amount: -res.bhxhMinor),
              _TaxLine(label: 'Trích BHYT (1.5%)', amount: -res.bhytMinor),
              _TaxLine(label: 'Trích BHTN (1%)', amount: -res.bhtnMinor),
              _TaxLine(
                label: 'Giảm trừ bản thân',
                amount: res.personalDeductionMinor,
              ),
              if (res.dependentDeductionMinor > 0)
                _TaxLine(
                  label: 'Giảm trừ $_dependents người phụ thuộc',
                  amount: res.dependentDeductionMinor,
                ),
              _TaxLine(
                label: 'Thu nhập tính thuế TNCN',
                amount: res.taxableIncomeMinor,
              ),
              _TaxLine(
                label: _taxPolicy == VietnamTaxPolicy.law109Year2026
                    ? 'Thuế TNCN lũy tiến 5 bậc (Luật 109/2025)'
                    : 'Thuế TNCN lũy tiến 7 bậc (Kỳ 2025)',
                amount: -res.personalIncomeTaxMinor,
                highlightCoral: res.personalIncomeTaxMinor > 0,
              ),
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'LƯƠNG THỰC NHẬN (NET)',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    VndAmount.format(res.netSalaryMinor),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      color: c.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Tổng chi phí công ty chi trả: ${VndAmount.format(res.totalEmployerCostMinor)}',
                style: TextStyle(
                  fontSize: 11.8,
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (res.brackets.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: res.brackets
                      .map(
                        (b) => LifeOsStatusPill(
                          label:
                              '${b.label} (${b.ratePercent}%): ${VndAmount.format(b.taxMinor)}',
                          tone: LifeOsAccentTone.blue,
                        ),
                      )
                      .toList(),
                ),
              ],
              if (wallets.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('salary_wallet_selector'),
                  isExpanded: true,
                  initialValue: resolvedWalletId,
                  decoration: const InputDecoration(
                    labelText: 'Chọn Ví nhận lương',
                    isDense: true,
                  ),
                  items: wallets
                      .map(
                        (w) => DropdownMenuItem(
                          value: w.id,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${w.name} (${VndAmount.format(w.balanceMinor)})',
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedWalletId = v);
                  },
                ),
              ],
              const SizedBox(height: 14),
              LifeOsPrimaryCtaButton(
                key: const Key('record_net_salary_to_wallet_btn'),
                label:
                    'Ghi Lương Thực Nhận ${VndAmount.format(res.netSalaryMinor)} Vào Ví',
                icon: Icons.add_card_rounded,
                onPressed: userId.isEmpty || _isSubmittingSalary
                    ? null
                    : () => _recordSalaryToWallet(
                        userId: userId,
                        wallets: wallets,
                        selectedWalletId: resolvedWalletId,
                        res: res,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteNote(
    BuildContext context,
    String userId,
    SmartLifeNoteEntity note,
  ) async {
    final bloc = context.read<DailyLifeBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Xác nhận xóa "${note.title}"?'),
        content: const Text(
          'Ghi chú này sẽ bị xóa vĩnh viễn khỏi Sổ tay LifeOS.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            key: Key('confirm_delete_note_${note.id}'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Xóa ghi chú'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      bloc.add(SmartNoteDeleted(userId: userId, noteId: note.id));
    }
  }

  Future<void> _showNoteEditorSheet(
    BuildContext context,
    String userId, {
    SmartLifeNoteEntity? existing,
  }) async {
    final bloc = context.read<DailyLifeBloc>();
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final contentCtrl = TextEditingController(text: existing?.content ?? '');
    const defaultCategories = [
      'Ghi chú nhanh',
      'Mã số & Wi-Fi',
      'Công việc & Ý tưởng',
      'Sách & Học tập',
    ];
    final categories = <String>[
      ...defaultCategories,
      if (existing != null &&
          existing.categoryTag.trim().isNotEmpty &&
          !defaultCategories.contains(existing.categoryTag))
        existing.categoryTag,
    ];
    var category = existing?.categoryTag ?? 'Ghi chú nhanh';
    if (!categories.contains(category)) {
      category = defaultCategories.first;
    }
    var pin = existing?.isPinned ?? true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModal) => Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    existing == null
                        ? 'Tạo Ghi chú Thông minh'
                        : 'Chỉnh sửa Ghi chú',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('smart_note_title_input'),
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tiêu đề ghi chú',
                      hintText:
                          'VD: Mã két sắt, Lịch tiêm phòng cho bé, Ý tưởng...',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('smart_note_content_input'),
                    controller: contentCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Nội dung chi tiết / Checklist',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: const Key('smart_note_category_dropdown'),
                    isExpanded: true,
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Phân loại'),
                    items: categories
                        .map(
                          (t) => DropdownMenuItem(value: t, child: Text(t)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setModal(() => category = v);
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ghim lên đầu Sổ tay'),
                    value: pin,
                    onChanged: (v) => setModal(() => pin = v),
                  ),
                  const SizedBox(height: 8),
                  LifeOsPrimaryCtaButton(
                    key: const Key('confirm_save_smart_note_btn'),
                    label: existing == null
                        ? 'Lưu Ghi chú'
                        : 'Cập nhật Ghi chú',
                    icon: Icons.check_rounded,
                    onPressed: () {
                      final t = titleCtrl.text.trim();
                      if (t.isEmpty) {
                        LifeOsTopToast.show(
                          ctx,
                          'Vui lòng nhập tiêu đề ghi chú.',
                          kind: LifeOsToastKind.warning,
                        );
                        return;
                      }
                      bloc.add(
                        SmartNoteSaved(
                          userId: userId,
                          existingId: existing?.id,
                          title: t,
                          content: contentCtrl.text.trim(),
                          categoryTag: category,
                          mood: existing?.mood,
                          isPinned: pin,
                        ),
                      );
                      Navigator.of(sheetCtx).pop();
                    },
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

class _TaxLine extends StatelessWidget {
  final String label;
  final int amount;
  final bool bold;
  final bool highlightCoral;

  const _TaxLine({
    required this.label,
    required this.amount,
    this.bold = false,
    this.highlightCoral = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final formatted = amount < 0
        ? '-${VndAmount.format(amount.abs())}'
        : VndAmount.format(amount);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                fontSize: 12.8,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: bold ? c.textPrimary : c.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatted,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              color: highlightCoral ? const Color(0xFFEF4444) : c.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
