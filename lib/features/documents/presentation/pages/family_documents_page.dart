import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/document_vault_entity.dart';
import '../../domain/repositories/document_vault_repository.dart';
import '../bloc/document_vault_bloc.dart';

/// Screen 19: "Tài liệu gia đình / Tài liệu chung" following Unified LifeOS Design System.
class FamilyDocumentsPage extends StatelessWidget {
  const FamilyDocumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = TammySemanticColors.of(context);
    final dateFmt = DateFormat('dd/MM/yyyy');

    return BlocListener<DocumentVaultBloc, DocumentVaultState>(
      listenWhen: (p, c) => p.failure != c.failure || p.message != c.message,
      listener: (context, state) {
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
      child: Scaffold(
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
                  child: BlocBuilder<DocumentVaultBloc, DocumentVaultState>(
                    builder: (context, state) {
                      final visible = state.visibleDocuments;
                      return Center(
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
                                decoration: InputDecoration(
                                  hintText:
                                      'Tìm tài liệu, mã hợp đồng, biển số...',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  fillColor: c.surface,
                                ),
                                onChanged: (val) => context
                                    .read<DocumentVaultBloc>()
                                    .add(DocumentVaultSearchQueryChanged(val)),
                              ),
                              const SizedBox(height: 14),

                              // 4 Canonical Folder Cards (matching Sheet 1 & Sheet 2 Screen 19)
                              ...DocumentFolderCategory.values.map((folder) {
                                final count = state.countForFolder(folder);
                                final isSelected =
                                    state.selectedFolder == folder;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: LifeOsSoftCard(
                                    backgroundColor: isSelected
                                        ? c.primarySubtle
                                        : c.surface,
                                    borderColor: isSelected
                                        ? c.primary
                                        : c.separator,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    onTap: () =>
                                        context.read<DocumentVaultBloc>().add(
                                          DocumentVaultFolderFilterChanged(
                                            folder,
                                          ),
                                        ),
                                    child: Row(
                                      children: [
                                        const LifeOsIconSquircle(
                                          icon: Icons.folder_rounded,
                                          tone: LifeOsAccentTone.amber,
                                          size: 46,
                                          iconSize: 25,
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                folder.displayTitle,
                                                style: TextStyle(
                                                  fontSize: 15.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: c.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '$count tệp · ${folder.subtitleHint}',
                                                softWrap: true,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: c.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          isSelected
                                              ? Icons.filter_alt_off_rounded
                                              : Icons.chevron_right_rounded,
                                          color: isSelected
                                              ? c.primary
                                              : c.textSecondary,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),

                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                                  if (state.selectedFolder != null)
                                    TextButton(
                                      onPressed: () =>
                                          context.read<DocumentVaultBloc>().add(
                                            const DocumentVaultFolderFilterChanged(
                                              null,
                                            ),
                                          ),
                                      child: const Text('Xem tất cả'),
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
                                        'Chưa có tài liệu nào trong mục này',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Lưu trữ số hợp đồng thuê nhà, đăng ký xe, bảo hiểm TNDS và giấy tờ quan trọng kèm hạn gia hạn.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ...visible.map((doc) {
                                  final now = DateTime.now();
                                  final expired = doc.isExpired(now);
                                  final soon = doc.isExpiringSoon(now);
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
                                            tone: doc.isFamilyShared
                                                ? LifeOsAccentTone.emerald
                                                : LifeOsAccentTone.blue,
                                            size: 42,
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
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 14.5,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  [
                                                    doc.folder.displayTitle,
                                                    if (doc
                                                        .referenceCode
                                                        .isNotEmpty)
                                                      'Mã: ${doc.referenceCode}',
                                                    doc.isFamilyShared
                                                        ? 'Chung gia đình'
                                                        : 'Cá nhân',
                                                  ].join(' · '),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                                if (doc.note.isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    doc.note,
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: c.textPrimary,
                                                    ),
                                                  ),
                                                ],
                                                if (doc.expiryDate != null) ...[
                                                  const SizedBox(height: 6),
                                                  LifeOsStatusPill(
                                                    icon: Icons.event_rounded,
                                                    label: expired
                                                        ? 'Quá hạn: ${dateFmt.format(doc.expiryDate!)}'
                                                        : soon
                                                        ? 'Sắp hết hạn: ${dateFmt.format(doc.expiryDate!)}'
                                                        : 'Hiệu lực đến: ${dateFmt.format(doc.expiryDate!)}',
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
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            tooltip: 'Xóa tài liệu',
                                            onPressed: () => context
                                                .read<DocumentVaultBloc>()
                                                .add(
                                                  DocumentVaultDeleteRequested(
                                                    userId: user.id,
                                                    document: doc,
                                                  ),
                                                ),
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

  Future<void> _showAddDocumentDialog(
    BuildContext context, {
    required String userId,
    required String userName,
    String? familyId,
    DocumentFolderCategory? initialFolder,
  }) async {
    final titleCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var folder = initialFolder ?? DocumentFolderCategory.billsAndContracts;
    var shareWithFamily = familyId != null && familyId.isNotEmpty;
    DateTime? expiryDate;
    final bloc = context.read<DocumentVaultBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Thêm Tài liệu Gia đình'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<DocumentFolderCategory>(
                  isExpanded: true,
                  initialValue: folder,
                  decoration: const InputDecoration(
                    labelText: 'Thư mục lưu trữ',
                  ),
                  items: DocumentFolderCategory.values
                      .map(
                        (f) => DropdownMenuItem(
                          value: f,
                          child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(
                            f.displayTitle,
                          )),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => folder = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('document_title_input'),
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên tài liệu / hồ sơ',
                    hintText:
                        'VD: Bảo hiểm vật chất Toyota Cross / Hợp đồng điện',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Số hợp đồng / Mã tham chiếu (Tùy chọn)',
                    hintText: 'VD: HD-2026-8892',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú lưu trữ',
                    hintText: 'Nơi cất bản cứng hoặc người phụ trách...',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate:
                          expiryDate ??
                          DateTime.now().add(const Duration(days: 180)),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2036),
                    );
                    if (picked != null) {
                      setDialogState(() => expiryDate = picked);
                    }
                  },
                  icon: const Icon(Icons.event_available_rounded, size: 18),
                  label: Text(
                    expiryDate == null
                        ? 'Chọn ngày hết hạn / gia hạn (Tùy chọn)'
                        : 'Hết hạn: ${DateFormat('dd/MM/yyyy').format(expiryDate!)}',
                  ),
                ),
                if (familyId != null && familyId.isNotEmpty)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Chia sẻ trong Tài liệu chung Gia đình'),
                    value: shareWithFamily,
                    onChanged: (v) => setDialogState(() => shareWithFamily = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              key: const Key('submit_document_button'),
              onPressed: () {
                bloc.add(
                  DocumentVaultCreateSubmitted(
                    CreateDocumentVaultParams(
                      userId: userId,
                      userName: userName,
                      familyId: familyId,
                      shareWithFamily: shareWithFamily,
                      folder: folder,
                      title: titleCtrl.text,
                      referenceCode: codeCtrl.text,
                      note: noteCtrl.text,
                      expiryDate: expiryDate,
                    ),
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Lưu tài liệu'),
            ),
          ],
        ),
      ),
    );
  }
}
