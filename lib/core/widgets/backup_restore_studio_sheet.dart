import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../features/authentication/presentation/bloc/auth_bloc.dart';
import '../../features/backup/data/repositories/in_memory_backup_repository.dart';
import '../../features/backup/data/services/backup_file_share_service_impl.dart';
import '../../features/backup/domain/entities/backup_entities.dart';
import '../../features/backup/domain/repositories/backup_file_share_service.dart';
import '../../features/backup/domain/repositories/backup_repository.dart';
import '../../features/backup/domain/usecases/backup_usecases.dart';
import '../../features/backup/presentation/bloc/backup_bloc.dart';
import '../../features/backup/presentation/bloc/backup_event.dart';
import '../../features/backup/presentation/bloc/backup_state.dart';
import '../../features/budgets/presentation/bloc/budget_bloc.dart';
import '../../features/calendar/presentation/bloc/calendar_bloc.dart';
import '../../features/daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../features/tasks/presentation/bloc/task_bloc.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import '../../features/transactions/presentation/bloc/transaction_bloc.dart';
import '../../features/vehicles/presentation/bloc/vehicle_bloc.dart';
import '../backup/lifeos_backup_restore_engine.dart';
import '../di/dependency_injection.dart';
import '../utils/privacy_mask_formatter.dart';
import '../utils/vnd_amount.dart';
import 'lifeos_design_system.dart';

T? _tryBloc<T extends StateStreamableSource<Object?>>(BuildContext context) {
  try {
    return context.read<T>();
  } catch (_) {
    return null;
  }
}

Map<String, List<Map<String, dynamic>>> _collectFallbackSnapshot(
  BuildContext context,
) {
  final txListBloc = _tryBloc<TransactionListBloc>(context);
  final budgetBloc = _tryBloc<BudgetBloc>(context);
  final taskBloc = _tryBloc<TaskBloc>(context);
  final calBloc = _tryBloc<CalendarBloc>(context);
  final vehicleBloc = _tryBloc<VehicleBloc>(context);
  final dailyBloc = _tryBloc<DailyLifeBloc>(context);

  final txs =
      txListBloc?.state.allTransactions ?? const <TransactionEntity>[];
  final wallets = txListBloc?.state.wallets ?? const <WalletEntity>[];
  final budgets = budgetBloc?.state.budgets ?? const [];
  final tasks = taskBloc?.state.tasks ?? const [];
  final events = calBloc?.state.events ?? const [];
  final vehicles = vehicleBloc?.state.vehicles ?? const [];
  final notes = dailyBloc?.state.snapshot.notes ?? const [];

  return <String, List<Map<String, dynamic>>>{
    BackupCollectionCatalog.wallets: wallets
        .map(
          (w) => <String, dynamic>{
            'id': w.id,
            'ownerId': w.ownerId,
            'name': w.name,
            'type': w.type.name,
            'balanceMinor': w.balanceMinor,
          },
        )
        .toList(),
    BackupCollectionCatalog.transactions: txs
        .map(
          (t) => <String, dynamic>{
            'id': t.id,
            'ownerId': t.ownerId,
            'walletId': t.walletId,
            if (t.targetWalletId != null) 'targetWalletId': t.targetWalletId,
            'kind': t.kind.name,
            'direction': t.direction,
            'categoryName': t.categoryName,
            'merchant': t.merchant,
            'amountMinor': t.amountMinor,
            'currencyCode': t.currencyCode,
            'verification': t.verification.name,
            'occurredAt': t.occurredAt.toUtc().toIso8601String(),
          },
        )
        .toList(),
    BackupCollectionCatalog.budgets: budgets
        .map(
          (b) => <String, dynamic>{
            'id': b.id,
            'ownerId': b.ownerId,
            'categoryId': b.categoryId,
            'categoryName': b.categoryName,
            'monthKey': b.monthKey,
            'limitMinor': b.limitMinor,
          },
        )
        .toList(),
    BackupCollectionCatalog.tasks: tasks
        .map(
          (t) => <String, dynamic>{
            'id': t.id,
            'title': t.title,
            'status': t.status.name,
          },
        )
        .toList(),
    BackupCollectionCatalog.events: events
        .map(
          (e) => <String, dynamic>{
            'id': e.id,
            'title': e.title,
            'startsAt': e.startsAt.toUtc().toIso8601String(),
            'endsAt': e.endsAt.toUtc().toIso8601String(),
          },
        )
        .toList(),
    BackupCollectionCatalog.vehicles: vehicles
        .map(
          (v) => <String, dynamic>{
            'id': v.id,
            'name': v.name,
            'plateNumber': v.plateNumber,
            'currentOdometerKm': v.currentOdometerKm,
          },
        )
        .toList(),
    BackupCollectionCatalog.notes: notes
        .map(
          (n) => <String, dynamic>{
            'id': n.id,
            'title': n.title,
            'content': n.content,
          },
        )
        .toList(),
  };
}

BackupBloc _resolveBackupBloc(BuildContext context) {
  if (sl.isRegistered<BackupBloc>()) {
    return sl<BackupBloc>();
  }
  final hasBackupDi =
      sl.isRegistered<BackupRepository>() ||
      sl.isRegistered<BackupFileShareService>();
  final shareService = sl.isRegistered<BackupFileShareService>()
      ? sl<BackupFileShareService>()
      : MethodChannelBackupFileShareService(invokePlatformShare: hasBackupDi);
  final repository = sl.isRegistered<BackupRepository>()
      ? sl<BackupRepository>()
      : InMemorySnapshotBackupRepository(
          initialCollections: _collectFallbackSnapshot(context),
        );
  return BackupBloc(
    loadSummary: LoadBackupOwnerSummaryUseCase(repository),
    exportFullBackup: ExportFullBackupUseCase(repository),
    exportTransactionsCsv: ExportTransactionsCsvUseCase(repository),
    previewArchive: PreviewBackupArchiveUseCase(repository),
    restoreArchive: RestoreBackupArchiveUseCase(repository),
    fileShareService: shareService,
  );
}

/// Complete Encrypted & Checksummed Backup & Restore Studio Sheet.
/// Supports paginated full-history export (`v3`), OWASP-safe CSV file sharing,
/// backward-compatible `v1`/`v2`/`v3` integrity preview, idempotent restore
/// across all owner collections, and post-commit per-wallet balance verification.
Future<void> showLifeOsBackupRestoreSheet(
  BuildContext context, {
  String? userIdOverride,
  BackupBloc? backupBlocOverride,
}) async {
  final authUser = _tryBloc<AuthBloc>(context)?.state.user;
  final userId = userIdOverride ?? authUser?.id ?? 'local_user';
  final ownsBloc = backupBlocOverride == null;
  final bloc =
      (backupBlocOverride ?? _resolveBackupBloc(context))
        ..add(BackupSummaryRequested(userId));

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => ownsBloc
        ? BlocProvider<BackupBloc>.value(
            value: bloc,
            child: _BackupRestoreStudioBody(userId: userId),
          )
        : BlocProvider<BackupBloc>.value(
            value: bloc,
            child: _BackupRestoreStudioBody(userId: userId),
          ),
  );
  if (ownsBloc) {
    await bloc.close();
  }
}

class _BackupRestoreStudioBody extends StatefulWidget {
  final String userId;

  const _BackupRestoreStudioBody({required this.userId});

  @override
  State<_BackupRestoreStudioBody> createState() =>
      _BackupRestoreStudioBodyState();
}

class _BackupRestoreStudioBodyState extends State<_BackupRestoreStudioBody> {
  bool _isRestoreTab = false;
  final TextEditingController _exportPassCtrl = TextEditingController();
  final TextEditingController _importPayloadCtrl = TextEditingController();
  final TextEditingController _importPassCtrl = TextEditingController();
  BackupRestoreMode _restoreMode = BackupRestoreMode.merge;
  bool _explicitReplaceConfirmed = false;
  bool _revealRawPreview = false;

  @override
  void dispose() {
    _exportPassCtrl.dispose();
    _importPayloadCtrl.dispose();
    _importPassCtrl.dispose();
    super.dispose();
  }

  void _runPreview(BuildContext context) {
    context.read<BackupBloc>().add(
      BackupArchivePreviewRequested(
        rawArchiveText: _importPayloadCtrl.text,
        passphrase: _importPassCtrl.text,
      ),
    );
  }

  void _applyRestore(BuildContext context, BackupState state) {
    if (state.preview == null) {
      _runPreview(context);
      return;
    }
    if (_restoreMode == BackupRestoreMode.replaceConfirmed &&
        !_explicitReplaceConfirmed) {
      LifeOsTopToast.show(
        context,
        'Vui lòng tích chọn xác nhận trước khi dùng chế độ Ghi đè.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }
    context.read<BackupBloc>().add(
      BackupRestoreSubmitted(
        targetUserId: widget.userId,
        mode: _restoreMode,
        explicitReplaceConfirmation: _explicitReplaceConfirmed,
      ),
    );
  }

  LifeOsToastKind _mapToastKind(BackupToastTone tone) => switch (tone) {
    BackupToastTone.success => LifeOsToastKind.success,
    BackupToastTone.info => LifeOsToastKind.info,
    BackupToastTone.warning => LifeOsToastKind.warning,
    BackupToastTone.error => LifeOsToastKind.error,
  };

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    return BlocConsumer<BackupBloc, BackupState>(
      listenWhen: (prev, curr) =>
          curr.toastFeedback != null &&
          prev.toastFeedback?.sequence != curr.toastFeedback?.sequence,
      listener: (ctx, state) {
        final fb = state.toastFeedback;
        if (fb == null) return;
        LifeOsTopToast.show(
          ctx,
          fb.messageVi,
          kind: _mapToastKind(fb.tone),
        );
      },
      builder: (context, state) {
        final summary = state.summary;
        final isBusy = state.isBusy;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.84,
            maxChildSize: 0.94,
            minChildSize: 0.52,
            builder: (_, scrollCtrl) => LiquidGlassSheetFrame(
              showHandle: true,
              child: ListView(
                key: const Key('backup_restore_sheet_list_view'),
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                children: [
                  Row(
                    children: [
                      const LifeOsIconSquircle(
                        icon: Icons.backup_outlined,
                        tone: LifeOsAccentTone.emerald,
                        size: 40,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sao lưu & Khôi phục Toàn vẹn',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                            Text(
                              'Xuất toàn bộ lịch sử nhiều tháng, kiểm tra SHA-256 và đối soát số dư ví',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LifeOsSegmentedPills<bool>(
                    selected: _isRestoreTab,
                    options: const [
                      (false, 'Xuất sao lưu', Icons.upload_file_rounded),
                      (true, 'Khôi phục dữ liệu', Icons.restore_page_outlined),
                    ],
                    onChanged: (v) => setState(() => _isRestoreTab = v),
                  ),
                  if (isBusy) ...[
                    const SizedBox(height: 10),
                    if (state.progress?.fraction != null) ...[
                      LinearProgressIndicator(
                        value: state.progress!.fraction,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      state.progress?.stageLabelVi ??
                          'Đang xử lý dữ liệu sao lưu...',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (!_isRestoreTab)
                    ..._buildExportTab(context, c, state, summary, isBusy)
                  else
                    ..._buildRestoreTab(context, c, state, dateFmt, isBusy),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildExportTab(
    BuildContext context,
    TammySemanticColors c,
    BackupState state,
    BackupOwnerDataSummary? summary,
    bool isBusy,
  ) {
    final totalRecords = summary?.totalRecordCount ?? 0;
    final loadingSummary =
        state.operation == BackupOperationKind.loadingSummary &&
        summary == null;

    return [
      LifeOsMintHeroCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loadingSummary
                  ? 'Đang thống kê toàn bộ dữ liệu...'
                  : 'Dữ liệu hiện có: $totalRecords bản ghi',
              softWrap: true,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            if (summary != null)
              Text(
                'Ví (${summary.walletCount}) · Giao dịch (${summary.transactionCount}) · Ngân sách (${summary.budgetCount}) · Lịch (${summary.eventCount}) · Việc (${summary.taskCount}) · Xe (${summary.vehicleCount}) · Ghi chú (${summary.noteCount})',
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.2,
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              )
            else if (state.summaryError != null)
              Text(
                state.summaryError!,
                softWrap: true,
                style: TextStyle(fontSize: 12.2, color: c.error),
              )
            else
              Text(
                'Tự động đọc phân trang toàn bộ lịch sử không giới hạn tháng hay mốc 100 giao dịch.',
                softWrap: true,
                style: TextStyle(fontSize: 12.2, color: c.textSecondary),
              ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('backup_export_passphrase_field'),
              controller: _exportPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Mật khẩu mã hóa bản sao lưu (khuyên dùng)',
                hintText: 'Để trống nếu xuất JSON kiểm tra SHA-256',
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('backup_export_json_btn'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: isBusy
                      ? null
                      : () {
                          setState(() => _revealRawPreview = false);
                          context.read<BackupBloc>().add(
                            BackupExportJsonRequested(
                              userId: widget.userId,
                              passphrase: _exportPassCtrl.text,
                            ),
                          );
                        },
                  icon: const Icon(Icons.enhanced_encryption_outlined, size: 18),
                  label: const Text('Tạo bản sao lưu đầy đủ'),
                ),
                OutlinedButton.icon(
                  key: const Key('backup_export_csv_btn'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: isBusy
                      ? null
                      : () {
                          context.read<BackupBloc>().add(
                            BackupExportCsvRequested(widget.userId),
                          );
                        },
                  icon: const Icon(Icons.table_view_rounded, size: 18),
                  label: const Text('Xuất giao dịch CSV'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LifeOsDetailsDiscloseSection(
              toggleKey: const Key('backup_export_details_toggle'),
              label: 'Chi tiết',
              expandedLabel: 'Thu gọn',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Định dạng Schema v3 · Kiểm tra toàn vẹn SHA-256 · Mã hóa luồng HMAC-SHA256-4096 EtM khi có mật khẩu · Xuất trực tiếp thành tệp (không lưu vào bộ nhớ tạm).',
                    softWrap: true,
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                  if (summary != null && summary.extendedCount > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Mục mở rộng khác (${summary.extendedCount}): danh mục, hóa đơn, bảo dưỡng xe, quỹ cá nhân, tủ thuốc, chỉ số điện nước, giấy tờ (chỉ metadata)...',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  for (final limit in BackupCollectionCatalog.defaultLimitationsVi)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '• $limit',
                        softWrap: true,
                        style: TextStyle(fontSize: 11.5, color: c.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (state.lastExportedArchive != null) ...[
        const SizedBox(height: 10),
        LifeOsSoftCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Nội dung gói sao lưu (mặc định đang che bảo vệ)',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('backup_toggle_raw_preview_btn'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () =>
                        setState(() => _revealRawPreview = !_revealRawPreview),
                    icon: Icon(
                      _revealRawPreview
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 16,
                    ),
                    label: Text(_revealRawPreview ? 'Ẩn bớt' : 'Mở xem'),
                  ),
                ],
              ),
              if (_revealRawPreview)
                SelectableText(
                  state.lastExportedArchive!,
                  maxLines: 6,
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                )
              else
                Text(
                  '${PrivacyMaskFormatter.maskNotePreview(state.lastExportedArchive!)}\n••••••••••••••••••••',
                  softWrap: true,
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildRestoreTab(
    BuildContext context,
    TammySemanticColors c,
    BackupState state,
    DateFormat dateFmt,
    bool isBusy,
  ) {
    final preview = state.preview;
    final report = state.lastRestoreReport;

    return [
      LifeOsSoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  key: const Key('backup_paste_clipboard_chip'),
                  avatar: Icon(
                    Icons.content_paste_rounded,
                    size: 16,
                    color: c.primary,
                  ),
                  label: const Text('Dán từ bộ nhớ tạm'),
                  onPressed: isBusy
                      ? null
                      : () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          final txt = data?.text?.trim() ?? '';
                          if (txt.isEmpty || !context.mounted) return;
                          setState(() => _importPayloadCtrl.text = txt);
                          _runPreview(context);
                        },
                ),
                if (state.lastExportedArchive != null)
                  ActionChip(
                    key: const Key('backup_use_recent_archive_chip'),
                    label: const Text('Dùng bản vừa xuất'),
                    onPressed: isBusy
                        ? null
                        : () {
                            setState(
                              () => _importPayloadCtrl.text =
                                  state.lastExportedArchive!,
                            );
                            _runPreview(context);
                          },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('backup_import_payload_field'),
              controller: _importPayloadCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Dán nội dung JSON / .lfbk sao lưu tại đây...',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('backup_import_passphrase_field'),
              controller: _importPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Mật khẩu giải mã (nếu tệp có khóa)',
                prefixIcon: Icon(Icons.key_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('backup_preview_validate_btn'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: isBusy ? null : () => _runPreview(context),
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: const Text('Kiểm tra toàn vẹn & Xem trước'),
            ),
          ],
        ),
      ),
      if (state.previewError != null) ...[
        const SizedBox(height: 10),
        LifeOsSoftCard(
          borderColor: c.error,
          child: Text(
            state.previewError!,
            softWrap: true,
            style: TextStyle(
              fontSize: 12.8,
              fontWeight: FontWeight.w700,
              color: c.error,
            ),
          ),
        ),
      ],
      if (preview != null) ...[
        const SizedBox(height: 10),
        LifeOsMintHeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  LifeOsStatusPill(
                    icon: Icons.verified_rounded,
                    label: preview.wasEncrypted
                        ? 'Đã giải mã & khớp SHA-256'
                        : 'Khớp toàn vẹn SHA-256',
                    tone: LifeOsAccentTone.emerald,
                  ),
                  LifeOsStatusPill(
                    label: 'Schema v${preview.schemaVersion}',
                    tone: LifeOsAccentTone.blue,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Tổng ${preview.totalRecordCount} bản ghi (${dateFmt.format(preview.exportedAt.toLocal())})',
                softWrap: true,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ví: ${preview.walletCount} · Giao dịch: ${preview.transactionCount} · Ngân sách: ${preview.budgetCount} · Lịch: ${preview.eventCount} · Việc: ${preview.taskCount} · Xe: ${preview.vehicleCount} · Ghi chú: ${preview.noteCount}',
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.2,
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              LifeOsDetailsDiscloseSection(
                toggleKey: const Key('backup_preview_details_toggle'),
                label: 'Chi tiết',
                expandedLabel: 'Thu gọn',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mã SHA-256 nội dung: ${preview.archiveSha256}',
                      softWrap: true,
                      style: TextStyle(fontSize: 11.5, color: c.textSecondary),
                    ),
                    if (preview.extendedCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Bản ghi mở rộng: ${preview.extendedCount} mục',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: c.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    for (final w in preview.warnings)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '• $w',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    for (final l in preview.limitationsVi)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '• $l',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<BackupRestoreMode>(
                key: const Key('backup_restore_mode_dropdown'),
                isExpanded: true,
                initialValue: _restoreMode,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Chế độ khôi phục',
                ),
                items: BackupRestoreMode.values
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(m.labelVi),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: isBusy
                    ? null
                    : (m) {
                        if (m != null) {
                          setState(() {
                            _restoreMode = m;
                            if (m != BackupRestoreMode.replaceConfirmed) {
                              _explicitReplaceConfirmed = false;
                            }
                          });
                        }
                      },
              ),
              if (_restoreMode == BackupRestoreMode.replaceConfirmed)
                CheckboxListTile(
                  key: const Key('backup_replace_confirm_checkbox'),
                  contentPadding: EdgeInsets.zero,
                  value: _explicitReplaceConfirmed,
                  onChanged: isBusy
                      ? null
                      : (v) => setState(
                          () => _explicitReplaceConfirmed = v ?? false,
                        ),
                  title: Text(
                    'Tôi hiểu chế độ Ghi đè sẽ thay thế bản ghi hiện tại bằng bản sao lưu này',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.error,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('backup_apply_restore_btn'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: isBusy
                      ? null
                      : () => _applyRestore(context, state),
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: Text(
                    report != null && report.isPartialFailure
                        ? 'Thử lại khôi phục tiếp'
                        : 'Thực hiện khôi phục',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      if (state.restoreError != null) ...[
        const SizedBox(height: 10),
        LifeOsSoftCard(
          borderColor: c.error,
          child: Text(
            state.restoreError!,
            softWrap: true,
            style: TextStyle(
              fontSize: 12.6,
              fontWeight: FontWeight.w700,
              color: c.error,
            ),
          ),
        ),
      ],
      if (report != null) ...[
        const SizedBox(height: 10),
        _RestoreReportCard(report: report),
      ],
    ];
  }
}

class _RestoreReportCard extends StatelessWidget {
  final BackupRestoreExecutionReport report;

  const _RestoreReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final borderColor = report.isCleanSuccess
        ? c.primary
        : (report.isPartialFailure ? c.error : c.warning);
    final headlineColor = report.isCleanSuccess
        ? c.primary
        : (report.isPartialFailure ? c.error : c.warning);

    return LifeOsSoftCard(
      key: const Key('backup_restore_report_card'),
      borderColor: borderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              LifeOsStatusPill(
                icon: report.isCleanSuccess
                    ? Icons.check_circle_outline_rounded
                    : Icons.warning_amber_rounded,
                label: report.isCleanSuccess
                    ? 'Khôi phục hoàn tất'
                    : (report.isPartialFailure
                          ? 'Khôi phục gián đoạn một phần'
                          : 'Cảnh báo lệch số dư ví'),
                tone: report.isCleanSuccess
                    ? LifeOsAccentTone.emerald
                    : (report.isPartialFailure
                          ? LifeOsAccentTone.coral
                          : LifeOsAccentTone.amber),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Đã ghi thật: ${report.committedCount} · Bỏ qua trùng: ${report.skippedCount} · Lỗi/Chưa ghi: ${report.failedCount}',
            softWrap: true,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          for (final line in report.detailsVi)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $line',
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.4,
                  fontWeight: FontWeight.w700,
                  color: headlineColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          if (report.perCollectionStats.isNotEmpty ||
              report.walletBalanceChecks.isNotEmpty) ...[
            const SizedBox(height: 6),
            LifeOsDetailsDiscloseSection(
              toggleKey: const Key('backup_report_details_toggle'),
              label: 'Chi tiết',
              expandedLabel: 'Thu gọn',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final stat in report.perCollectionStats)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${stat.labelVi}: đã ghi ${stat.committedCount}/${stat.plannedCount}'
                        '${stat.skippedCount > 0 ? ', bỏ qua ${stat.skippedCount}' : ''}'
                        '${stat.failedCount > 0 ? ', lỗi ${stat.failedCount}' : ''}',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 11.8,
                          color: c.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  if (report.walletBalanceChecks.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Đối soát số dư theo từng ví:',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final check in report.walletBalanceChecks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          check.matched
                              ? '✓ ${check.walletName}: ${VndAmount.format(check.actualBalanceMinor)} (khớp)'
                              : '✕ ${check.walletName}: sao lưu ${VndAmount.format(check.expectedBalanceMinor)} ≠ thực tế ${VndAmount.format(check.actualBalanceMinor)}',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 11.8,
                            fontWeight: check.matched
                                ? FontWeight.w500
                                : FontWeight.w700,
                            color: check.matched ? c.textSecondary : c.error,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
