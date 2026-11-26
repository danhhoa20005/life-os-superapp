import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/privacy_mask_formatter.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/document_vault_entity.dart';
import '../../domain/repositories/document_vault_repository.dart';
import '../bloc/document_vault_bloc.dart';

/// Screen 19: "Tài liệu gia đình / Tài liệu chung" following Unified LifeOS Design System.
class FamilyDocumentsPage extends StatefulWidget {
  const FamilyDocumentsPage({super.key});

  @override
  State<FamilyDocumentsPage> createState() => _FamilyDocumentsPageState();
}

class _FamilyDocumentsPageState extends State<FamilyDocumentsPage> {
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');

  late final TextEditingController _searchCtrl;
  final Set<String> _revealedDocIds = <String>{};

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(
      text: context.read<DocumentVaultBloc>().state.searchQuery,
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearAllFilters(BuildContext context) {
    _searchCtrl.clear();
    context.read<DocumentVaultBloc>().add(const DocumentVaultFiltersCleared());
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select(
      (AuthBloc b) => b.state.user == null
          ? null
          : (
              id: b.state.user!.id,
              fullName: b.state.user!.fullName,
              activeFamilyId: b.state.user!.activeFamilyId,
            ),
    );
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = TammySemanticColors.of(context);

    return BlocConsumer<DocumentVaultBloc, DocumentVaultState>(
      buildWhen: (p, n) =>
          p.documents != n.documents ||
          p.selectedFolder != n.selectedFolder ||
          p.searchQuery != n.searchQuery,
      listenWhen: (p, n) =>
          p.searchQuery != n.searchQuery ||
          (n.failure != null && p.failure != n.failure) ||
          (n.message != null && p.message != n.message),
      listener: (context, state) {
        if (state.searchQuery.isEmpty && _searchCtrl.text.isNotEmpty) {
          _searchCtrl.clear();
        }
        if (state.failure != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text('⚠ ${state.failure!.message}')),
          );
        } else if (state.message != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text('✓ ${state.message!}')),
          );
        }
      },
      builder: (context, state) {
        final visible = state.visibleDocuments;
        return Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              child: Column(
                children: [
                  LifeOsTopBrandHeader(
                    title: 'Tài liệu gia đình',
                    showBackButton: true,
                    trailingAction: IconButton.filledTonal(
                      tooltip: 'Thêm tài liệu mới',
                      onPressed: () => _showAddDocumentDialog(
                        context,
                        userId: user.id,
                        userName: user.fullName,
                        familyId: user.activeFamilyId,
                      ),
                      icon: const Icon(Icons.add_rounded),
                    ),
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
                            // Search bar ("Tìm tài liệu...")
                            TextField(
                              key: const Key('documents_search_field'),
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText:
                                    'Tìm tài liệu, mã hợp đồng, biển số (có dấu / không dấu)...',
                                prefixIcon: const Icon(Icons.search_rounded),
                                fillColor: c.surface,
                                suffixIcon:
                                    state.searchQuery.isEmpty &&
                                        _searchCtrl.text.isEmpty
                                    ? null
                                    : IconButton(
                                        key: const Key(
                                          'documents_search_clear_btn',
                                        ),
                                        tooltip: 'Xóa tìm kiếm',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          context.read<DocumentVaultBloc>().add(
                                            const DocumentVaultSearchQueryChanged(
                                              '',
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                        ),
                                      ),
                              ),
                              onChanged: (val) => context
                                  .read<DocumentVaultBloc>()
                                  .add(DocumentVaultSearchQueryChanged(val)),
                            ),
                            const SizedBox(height: 10),

                            // Quick "Tất cả" + Folder Filter Chips
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ChoiceChip(
                                    key: const Key('documents_filter_all_chip'),
                                    label: Text(
                                      'Tất cả (${state.documents.length})',
                                    ),
                                    selected: !state.hasActiveFilters,
                                    visualDensity: VisualDensity.compact,
                                    onSelected: (_) =>
                                        _clearAllFilters(context),
                                  ),
                                  for (final folder
                                      in DocumentFolderCategory.values) ...[
                                    const SizedBox(width: 6),
                                    ChoiceChip(
                                      label: Text(
                                        '${folder.displayTitle} (${state.countForFolder(folder)})',
                                      ),
                                      selected: state.selectedFolder == folder,
                                      visualDensity: VisualDensity.compact,
                                      onSelected: (_) =>
                                          context.read<DocumentVaultBloc>().add(
                                            DocumentVaultFolderFilterChanged(
                                              folder,
                                            ),
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // 2x2 Bento Folder Grid (UI/UX Pro Max — Distinct 3D Nano Banana Icons)
                            LayoutBuilder(
                              builder: (ctx, box) {
                                final isTwoCol = box.maxWidth >= 280;
                                final cardWidth = isTwoCol
                                    ? (box.maxWidth - 10) / 2
                                    : box.maxWidth;
                                return Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: DocumentFolderCategory.values.map((
                                    folder,
                                  ) {
                                    final count = state.countForFolder(folder);
                                    final isSelected =
                                        state.selectedFolder == folder;
                                    final folderIcon = switch (folder) {
                                      DocumentFolderCategory
                                          .billsAndContracts =>
                                        Icons.electric_bolt_rounded,
                                      DocumentFolderCategory.vehiclePapers =>
                                        Icons.directions_car_outlined,
                                      DocumentFolderCategory
                                          .insuranceAndHealth =>
                                        Icons.favorite_outline_rounded,
                                      DocumentFolderCategory.importantDocs =>
                                        Icons.folder_open_rounded,
                                    };
                                    final folderTone = switch (folder) {
                                      DocumentFolderCategory
                                          .billsAndContracts =>
                                        LifeOsAccentTone.amber,
                                      DocumentFolderCategory.vehiclePapers =>
                                        LifeOsAccentTone.blue,
                                      DocumentFolderCategory
                                          .insuranceAndHealth =>
                                        LifeOsAccentTone.coral,
                                      DocumentFolderCategory.importantDocs =>
                                        LifeOsAccentTone.purple,
                                    };
                                    return SizedBox(
                                      width: cardWidth,
                                      child: LifeOsSoftCard(
                                        backgroundColor: isSelected
                                            ? c.primarySubtle
                                            : c.surface,
                                        borderColor: isSelected
                                            ? c.primary
                                            : c.separator,
                                        padding: const EdgeInsets.all(12),
                                        onTap: () => context
                                            .read<DocumentVaultBloc>()
                                            .add(
                                              DocumentVaultFolderFilterChanged(
                                                folder,
                                              ),
                                            ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                LifeOsIconSquircle(
                                                  icon: folderIcon,
                                                  tone: folderTone,
                                                  size: 38,
                                                  iconSize: 20,
                                                ),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? c.primary
                                                        : c.surfaceRaised,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '$count tệp',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: isSelected
                                                          ? Colors.white
                                                          : c.textSecondary,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              folder.displayTitle,
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 13.8,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              folder.subtitleHint,
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),

                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    state.selectedFolder == null
                                        ? 'Hồ sơ & Tài liệu đã lưu (${visible.length})'
                                        : '${state.selectedFolder!.displayTitle} (${visible.length})',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                ),
                                if (state.hasActiveFilters)
                                  TextButton.icon(
                                    onPressed: () => _clearAllFilters(context),
                                    icon: const Icon(
                                      Icons.filter_alt_off_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Xem tất cả'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            if (visible.isEmpty)
                              LifeOsMintHeroCard(
                                child: Column(
                                  children: [
                                    const LifeOsIconSquircle(
                                      icon: Icons.description_outlined,
                                      tone: LifeOsAccentTone.emerald,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      state.hasActiveFilters
                                          ? 'Không tìm thấy tài liệu khớp bộ lọc'
                                          : 'Chưa có tài liệu nào trong mục này',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      state.hasActiveFilters
                                          ? 'Bấm "Xóa bộ lọc" để hiển thị lại toàn bộ hồ sơ & tài liệu đã lưu.'
                                          : 'Lưu trữ số hợp đồng thuê nhà, đăng ký xe, bảo hiểm TNDS và giấy tờ quan trọng kèm hạn gia hạn.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                    if (state.hasActiveFilters) ...[
                                      const SizedBox(height: 12),
                                      FilledButton.tonalIcon(
                                        key: const Key(
                                          'documents_reset_filters_btn',
                                        ),
                                        onPressed: () =>
                                            _clearAllFilters(context),
                                        icon: const Icon(
                                          Icons.filter_alt_off_rounded,
                                          size: 17,
                                        ),
                                        label: const Text('Xóa bộ lọc'),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            else
                              ...visible.map((doc) {
                                final now = DateTime.now();
                                final expired = doc.isExpired(now);
                                final soon = doc.isExpiringSoon(now);
                                final isRevealed = _revealedDocIds.contains(
                                  doc.id,
                                );
                                final hasSensitive =
                                    doc.referenceCode.trim().isNotEmpty ||
                                    doc.note.trim().isNotEmpty;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: LifeOsSoftCard(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        LifeOsIconSquircle(
                                          icon: doc.isFamilyShared
                                              ? Icons.folder_shared_outlined
                                              : Icons
                                                    .insert_drive_file_outlined,
                                          tone: expired
                                              ? LifeOsAccentTone.coral
                                              : soon
                                              ? LifeOsAccentTone.amber
                                              : LifeOsAccentTone.emerald,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                doc.title,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w800,
                                                  color: c.textPrimary,
                                                ),
                                              ),
                                              if (doc.referenceCode.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 2,
                                                      ),
                                                  child: Text(
                                                    isRevealed
                                                        ? 'Mã tham chiếu: ${doc.referenceCode}'
                                                        : 'Mã tham chiếu: ${PrivacyMaskFormatter.maskCode(doc.referenceCode)}',
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: c.primary,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              if (doc.note.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 3,
                                                      ),
                                                  child: Text(
                                                    isRevealed
                                                        ? doc.note
                                                        : PrivacyMaskFormatter.maskNotePreview(
                                                            doc.note,
                                                          ),
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: c.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              if (doc.expiryDate != null) ...[
                                                const SizedBox(height: 6),
                                                LifeOsStatusPill(
                                                  label: expired
                                                      ? 'Đã quá hạn: ${_dateFmt.format(doc.expiryDate!)}'
                                                      : soon
                                                      ? 'Sắp hết hạn: ${_dateFmt.format(doc.expiryDate!)}'
                                                      : 'Hiệu lực đến: ${_dateFmt.format(doc.expiryDate!)}',
                                                  tone: expired
                                                      ? LifeOsAccentTone.coral
                                                      : soon
                                                      ? LifeOsAccentTone.amber
                                                      : LifeOsAccentTone
                                                            .emerald,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (hasSensitive)
                                          IconButton(
                                            key: Key(
                                              'toggle_doc_sensitive_${doc.id}',
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            tooltip: isRevealed
                                                ? 'Ẩn mã & ghi chú'
                                                : 'Hiện mã & ghi chú',
                                            onPressed: () => setState(() {
                                              if (isRevealed) {
                                                _revealedDocIds.remove(doc.id);
                                              } else {
                                                _revealedDocIds.add(doc.id);
                                              }
                                            }),
                                            icon: Icon(
                                              isRevealed
                                                  ? Icons
                                                        .visibility_off_outlined
                                                  : Icons.visibility_outlined,
                                              size: 19,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                        IconButton(
                                          key: Key('edit_doc_btn_${doc.id}'),
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Sửa / Gia hạn tài liệu',
                                          onPressed: () =>
                                              _showAddDocumentDialog(
                                                context,
                                                userId: user.id,
                                                userName: user.fullName,
                                                familyId: user.activeFamilyId,
                                                existingDocument: doc,
                                              ),
                                          icon: Icon(
                                            Icons.edit_outlined,
                                            size: 19,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Xóa tài liệu',
                                          onPressed: () async {
                                            final ok = await showDestructiveConfirmDialog(
                                              context: context,
                                              title: 'Xóa tài liệu này?',
                                              message: doc.isFamilyShared
                                                  ? 'Tài liệu "${doc.title}" đang chia sẻ chung sẽ bị xóa khỏi Kho tài liệu gia đình.'
                                                  : 'Tài liệu "${doc.title}" sẽ bị xóa khỏi kho lưu trữ.',
                                              confirmLabel: 'Xóa tài liệu',
                                            );
                                            if (ok && context.mounted) {
                                              context
                                                  .read<DocumentVaultBloc>()
                                                  .add(
                                                    DocumentVaultDeleteRequested(
                                                      userId: user.id,
                                                      document: doc,
                                                    ),
                                                  );
                                            }
                                          },
                                          icon: Icon(
                                            Icons.delete_outline_rounded,
                                            size: 20,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),

                            const SizedBox(height: 14),
                            LifeOsPrimaryCtaButton(
                              icon: Icons.add_rounded,
                              label: 'Thêm tài liệu',
                              onPressed: () => _showAddDocumentDialog(
                                context,
                                userId: user.id,
                                userName: user.fullName,
                                familyId: user.activeFamilyId,
                                initialFolder: state.selectedFolder,
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
          ),
        );
      },
    );
  }

  Future<void> _showAddDocumentDialog(
    BuildContext context, {
    required String userId,
    required String userName,
    String? familyId,
    DocumentFolderCategory? initialFolder,
    DocumentVaultEntity? existingDocument,
  }) async {
    final bloc = context.read<DocumentVaultBloc>();
    await showDialog<void>(
      context: context,
      builder: (_) => _AddDocumentVaultDialog(
        bloc: bloc,
        userId: userId,
        userName: userName,
        familyId: familyId,
        initialFolder: initialFolder,
        existingDocument: existingDocument,
      ),
    );
  }
}

class _AddDocumentVaultDialog extends StatefulWidget {
  final DocumentVaultBloc bloc;
  final String userId;
  final String userName;
  final String? familyId;
  final DocumentFolderCategory? initialFolder;
  final DocumentVaultEntity? existingDocument;

  const _AddDocumentVaultDialog({
    required this.bloc,
    required this.userId,
    required this.userName,
    required this.familyId,
    this.initialFolder,
    this.existingDocument,
  });

  @override
  State<_AddDocumentVaultDialog> createState() =>
      _AddDocumentVaultDialogState();
}

class _AddDocumentVaultDialogState extends State<_AddDocumentVaultDialog> {
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');

  late final TextEditingController _titleCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _noteCtrl;
  late DocumentFolderCategory _folder;
  late bool _shareWithFamily;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingDocument;
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _codeCtrl = TextEditingController(text: existing?.referenceCode ?? '');
    _noteCtrl = TextEditingController(text: existing?.note ?? '');
    _folder =
        existing?.folder ??
        widget.initialFolder ??
        DocumentFolderCategory.billsAndContracts;
    _shareWithFamily =
        existing?.isFamilyShared ??
        (widget.familyId != null && widget.familyId!.isNotEmpty);
    _expiryDate = existing?.expiryDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _codeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existingDocument != null
            ? 'Sửa / Gia hạn Tài liệu'
            : 'Thêm Tài liệu Gia đình',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<DocumentFolderCategory>(
              isExpanded: true,
              initialValue: _folder,
              decoration: const InputDecoration(labelText: 'Thư mục lưu trữ'),
              items: DocumentFolderCategory.values
                  .map(
                    (f) => DropdownMenuItem(
                      value: f,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(f.displayTitle),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _folder = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('document_title_input'),
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên tài liệu / hồ sơ',
                hintText: 'VD: Bảo hiểm vật chất Toyota Cross / Hợp đồng điện',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Số hợp đồng / Mã tham chiếu (Tùy chọn)',
                hintText: 'VD: HD-2026-8892',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Ghi chú lưu trữ',
                hintText: 'Nơi cất bản cứng hoặc người phụ trách...',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            _expiryDate ??
                            DateTime.now().add(const Duration(days: 180)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null && mounted) {
                        setState(() => _expiryDate = picked);
                      }
                    },
                    icon: const Icon(Icons.event_available_rounded, size: 18),
                    label: Text(
                      _expiryDate == null
                          ? 'Chọn ngày hết hạn / gia hạn'
                          : 'Hết hạn: ${_dateFmt.format(_expiryDate!)}',
                    ),
                  ),
                ),
                if (_expiryDate != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Bỏ chọn ngày hết hạn',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _expiryDate = null),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ],
            ),
            if (widget.existingDocument == null &&
                widget.familyId != null &&
                widget.familyId!.isNotEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Chia sẻ trong Tài liệu chung Gia đình'),
                value: _shareWithFamily,
                onChanged: (v) => setState(() => _shareWithFamily = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('submit_document_button'),
          onPressed: () {
            if (_titleCtrl.text.trim().length < 2) {
              LifeOsTopToast.show(
                context,
                'Hãy nhập tên tài liệu hoặc hồ sơ (ít nhất 2 ký tự).',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            if (widget.existingDocument != null) {
              widget.bloc.add(
                DocumentVaultUpdateSubmitted(
                  UpdateDocumentVaultParams(
                    userId: widget.userId,
                    existing: widget.existingDocument!,
                    folder: _folder,
                    title: _titleCtrl.text,
                    referenceCode: _codeCtrl.text,
                    note: _noteCtrl.text,
                    expiryDate: _expiryDate,
                  ),
                ),
              );
            } else {
              widget.bloc.add(
                DocumentVaultCreateSubmitted(
                  CreateDocumentVaultParams(
                    userId: widget.userId,
                    userName: widget.userName,
                    familyId: widget.familyId,
                    shareWithFamily: _shareWithFamily,
                    folder: _folder,
                    title: _titleCtrl.text,
                    referenceCode: _codeCtrl.text,
                    note: _noteCtrl.text,
                    expiryDate: _expiryDate,
                  ),
                ),
              );
            }
            Navigator.of(context).pop();
          },
          child: Text(
            widget.existingDocument != null ? 'Cập nhật' : 'Lưu tài liệu',
          ),
        ),
      ],
    );
  }
}
