import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/app_colors.dart';
import '../../features/authentication/presentation/bloc/auth_bloc.dart';
import '../../features/budgets/presentation/bloc/budget_bloc.dart';
import '../../features/calendar/presentation/bloc/calendar_bloc.dart';
import '../../features/daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../features/tasks/presentation/bloc/task_bloc.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import '../../features/transactions/presentation/bloc/transaction_bloc.dart';
import '../../features/transactions/presentation/bloc/transaction_event.dart';
import '../../features/vehicles/presentation/bloc/vehicle_bloc.dart';
import '../backup/lifeos_backup_restore_engine.dart';
import '../di/dependency_injection.dart';
import '../services/native_app_updater_bridge.dart';
import 'lifeos_design_system.dart';

T? _tryBloc<T extends StateStreamableSource<Object?>>(BuildContext context) {
  try {
    return context.read<T>();
  } catch (_) {
    return null;
  }
}

/// Complete Encrypted & Checksummed Backup & Restore Studio Sheet (Section 21).
/// Supports OWASP-safe CSV export, password-encrypted `.lfbk` JSON export,
/// SHA-256 integrity preview, and non-destructive `merge` / `importAsNew` / guarded `replaceConfirmed`.
Future<void> showLifeOsBackupRestoreSheet(BuildContext context) async {
  final authUser = _tryBloc<AuthBloc>(context)?.state.user;
  final userId = authUser?.id ?? 'local_user';
  final txListBloc = _tryBloc<TransactionListBloc>(context);
  final txActionBloc = _tryBloc<TransactionActionBloc>(context);
  final budgetBloc = _tryBloc<BudgetBloc>(context);
  final taskBloc = _tryBloc<TaskBloc>(context);
  final calBloc = _tryBloc<CalendarBloc>(context);
  final vehicleBloc = _tryBloc<VehicleBloc>(context);
  final dailyBloc = _tryBloc<DailyLifeBloc>(context);

  Map<String, List<Map<String, dynamic>>> collectCurrentData() {
    final txs = txListBloc?.state.allTransactions ?? const <TransactionEntity>[];
    final wallets = txListBloc?.state.wallets ?? const <WalletEntity>[];
    final budgets = budgetBloc?.state.budgets ?? const [];
    final tasks = taskBloc?.state.tasks ?? const [];
    final events = calBloc?.state.events ?? const [];
    final vehicles = vehicleBloc?.state.vehicles ?? const [];
    final notes = dailyBloc?.state.snapshot.notes ?? const [];

    return <String, List<Map<String, dynamic>>>{
      'wallets': wallets
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
      'transactions': txs
          .map(
            (t) => <String, dynamic>{
              'id': t.id,
              'ownerId': t.ownerId,
              'walletId': t.walletId,
              'kind': t.kind.name,
              'categoryName': t.categoryName,
              'merchant': t.merchant,
              'amountMinor': t.amountMinor,
              'currencyCode': 'VND',
              'verification': t.verification.name,
              'occurredAt': t.occurredAt.toUtc().toIso8601String(),
            },
          )
          .toList(),
      'budgets': budgets
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
      'tasks': tasks
          .map(
            (t) => <String, dynamic>{
              'id': t.id,
              'title': t.title,
              'status': t.status.name,
            },
          )
          .toList(),
      'events': events
          .map(
            (e) => <String, dynamic>{
              'id': e.id,
              'title': e.title,
              'startsAt': e.startsAt.toUtc().toIso8601String(),
              'endsAt': e.endsAt.toUtc().toIso8601String(),
            },
          )
          .toList(),
      'vehicles': vehicles
          .map(
            (v) => <String, dynamic>{
              'id': v.id,
              'name': v.name,
              'plateNumber': v.plateNumber,
              'currentOdometerKm': v.currentOdometerKm,
            },
          )
          .toList(),
      'notes': notes
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

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _BackupRestoreStudioBody(
      userId: userId,
      collectCurrentData: collectCurrentData,
      txListBloc: txListBloc,
      txActionBloc: txActionBloc,
    ),
  );
}

class _BackupRestoreStudioBody extends StatefulWidget {
  final String userId;
  final Map<String, List<Map<String, dynamic>>> Function() collectCurrentData;
  final TransactionListBloc? txListBloc;
  final TransactionActionBloc? txActionBloc;

  const _BackupRestoreStudioBody({
    required this.userId,
    required this.collectCurrentData,
    this.txListBloc,
    this.txActionBloc,
  });

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
  BackupPreviewSummary? _previewSummary;
  Map<String, List<Map<String, dynamic>>>? _previewCollections;
  String? _previewError;
  BackupRestoreReport? _lastReport;
  bool _revealRawPreview = false;
  String? _lastExportedArchive;

  @override
  void dispose() {
    _exportPassCtrl.dispose();
    _importPayloadCtrl.dispose();
    _importPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _shareOrCopy(
    BuildContext context, {
    required String fileName,
    required String content,
    required String mimeType,
    required String title,
  }) async {
    await Clipboard.setData(ClipboardData(text: content));
    String? savedPath;
    if (sl.isRegistered<NativeAppUpdaterBridge>()) {
      savedPath = await sl<NativeAppUpdaterBridge>().shareTextFile(
        fileName: fileName,
        content: content,
        mimeType: mimeType,
        title: title,
      );
    }
    if (!context.mounted) return;
    LifeOsTopToast.show(
      context,
      savedPath != null
          ? 'Đã xuất tệp $fileName và sẵn sàng chia sẻ.'
          : 'Đã tạo bản sao lưu $fileName vào bộ nhớ tạm.',
      kind: LifeOsToastKind.success,
    );
  }

  void _runPreview() {
    final raw = _importPayloadCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _previewSummary = null;
        _previewCollections = null;
        _previewError = 'Vui lòng dán nội dung tệp sao lưu để kiểm tra.';
      });
      return;
    }
    try {
      final res = LifeOsBackupRestoreEngine.previewAndValidateArchive(
        raw,
        passphrase: _importPassCtrl.text.trim(),
      );
      setState(() {
        _previewSummary = res.summary;
        _previewCollections = res.collections;
        _previewError = null;
        _lastReport = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _previewSummary = null;
        _previewCollections = null;
        _previewError = e.message;
      });
    } catch (_) {
      setState(() {
        _previewSummary = null;
        _previewCollections = null;
        _previewError =
            'Không thể đọc tệp sao lưu — vui lòng kiểm tra mật khẩu hoặc toàn vẹn dữ liệu.';
      });
    }
  }

  void _applyRestore(BuildContext context) {
    final incoming = _previewCollections;
    final summary = _previewSummary;
    if (incoming == null || summary == null) {
      _runPreview();
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

    final existing = widget.collectCurrentData();
    final planned = LifeOsBackupRestoreEngine.applyRestorePlan(
      existingCollections: existing,
      incomingCollections: incoming,
      targetUserId: widget.userId,
      mode: _restoreMode,
      explicitReplaceConfirmation: _explicitReplaceConfirmed,
      sourceSchemaVersion: summary.schemaVersion,
    );

    // Commit newly imported non-duplicate transactions into live BLoC when available
    final txAction = widget.txActionBloc;
    final wallets = widget.txListBloc?.state.wallets ?? const <WalletEntity>[];
    if (txAction != null && wallets.isNotEmpty) {
      final existingIds = <String>{
        for (final e in existing['transactions'] ?? const [])
          (e['id'] ?? '').toString(),
      };
      final targetWalletId = wallets.first.id;
      for (final txMap
          in planned.resultingCollections['transactions'] ?? const []) {
        final id = (txMap['id'] ?? '').toString();
        if (existingIds.contains(id)) continue;
        final amt = (txMap['amountMinor'] as num?)?.toInt() ?? 0;
        if (amt <= 0) continue;
        final kindStr = (txMap['kind'] ?? 'expense').toString();
        final kind = kindStr == 'income'
            ? TransactionKind.income
            : TransactionKind.expense;
        txAction.add(
          TransactionCreateSubmitted(
            operationId: id.isNotEmpty ? 'restore_$id' : const Uuid().v4(),
            userId: widget.userId,
            walletId: targetWalletId,
            categoryName: (txMap['categoryName'] ?? 'Chi tiêu khác').toString(),
            kind: kind,
            amountMinor: amt,
            merchant: (txMap['merchant'] ?? 'Khôi phục sao lưu').toString(),
            occurredAt:
                DateTime.tryParse((txMap['occurredAt'] ?? '').toString()) ??
                DateTime.now(),
          ),
        );
      }
    }

    setState(() => _lastReport = planned.report);
    LifeOsTopToast.show(
      context,
      planned.report.detailsVi.first,
      kind: LifeOsToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final currentCols = widget.collectCurrentData();
    final totalRecords = currentCols.values.fold<int>(
      0,
      (s, list) => s + list.length,
    );
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
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
                          'Kiểm tra mã băm SHA-256 và mã hóa mật khẩu di động',
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
              const SizedBox(height: 12),
              if (!_isRestoreTab) ...[
                LifeOsMintHeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dữ liệu hiện có: $totalRecords bản ghi',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ví (${currentCols['wallets']!.length}) · Giao dịch (${currentCols['transactions']!.length}) · Ngân sách (${currentCols['budgets']!.length}) · Lịch (${currentCols['events']!.length}) · Việc (${currentCols['tasks']!.length})',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12.2,
                          color: c.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
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
                            onPressed: () {
                              final archive =
                                  LifeOsBackupRestoreEngine.createBackupArchive(
                                    ownerId: widget.userId,
                                    collections: currentCols,
                                    passphrase: _exportPassCtrl.text,
                                  );
                              setState(() {
                                _lastExportedArchive = archive;
                                _revealRawPreview = false;
                              });
                              final encrypted =
                                  _exportPassCtrl.text.trim().isNotEmpty;
                              _shareOrCopy(
                                context,
                                fileName: encrypted
                                    ? 'LifeOS_Backup.lfbk.json'
                                    : 'LifeOS_Backup_v2.json',
                                content: archive,
                                mimeType: 'application/json',
                                title: 'Bản sao lưu LifeOS',
                              );
                            },
                            icon: const Icon(
                              Icons.enhanced_encryption_outlined,
                              size: 18,
                            ),
                            label: const Text('Tạo bản sao lưu đầy đủ'),
                          ),
                          OutlinedButton.icon(
                            key: const Key('backup_export_csv_btn'),
                            onPressed: () {
                              final csv =
                                  LifeOsBackupRestoreEngine.exportTransactionsCsv(
                                    currentCols['transactions']!,
                                  );
                              _shareOrCopy(
                                context,
                                fileName: 'LifeOS_Transactions.csv',
                                content: csv,
                                mimeType: 'text/csv',
                                title: 'Sao kê giao dịch CSV',
                              );
                            },
                            icon: const Icon(Icons.table_view_rounded, size: 18),
                            label: const Text('Xuất giao dịch CSV'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_lastExportedArchive != null) ...[
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
                            TextButton(
                              key: const Key('backup_toggle_raw_preview_btn'),
                              onPressed: () => setState(
                                () => _revealRawPreview = !_revealRawPreview,
                              ),
                              child: Text(_revealRawPreview ? 'Ẩn bớt' : 'Mở xem'),
                            ),
                          ],
                        ),
                        if (_revealRawPreview)
                          SelectableText(
                            _lastExportedArchive!,
                            maxLines: 6,
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textSecondary,
                            ),
                          )
                        else
                          Text(
                            '••••••••••••••••••••••••••••••••••••••••',
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
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
                            onPressed: () async {
                              final data = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              final txt = data?.text?.trim() ?? '';
                              if (txt.isEmpty) return;
                              setState(() => _importPayloadCtrl.text = txt);
                              _runPreview();
                            },
                          ),
                          if (_lastExportedArchive != null)
                            ActionChip(
                              key: const Key('backup_use_recent_archive_chip'),
                              label: const Text('Dùng bản vừa xuất'),
                              onPressed: () {
                                setState(
                                  () => _importPayloadCtrl.text =
                                      _lastExportedArchive!,
                                );
                                _runPreview();
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
                        onPressed: _runPreview,
                        icon: const Icon(Icons.verified_outlined, size: 18),
                        label: const Text('Kiểm tra toàn vẹn & Xem trước'),
                      ),
                    ],
                  ),
                ),
                if (_previewError != null) ...[
                  const SizedBox(height: 10),
                  LifeOsSoftCard(
                    borderColor: c.error,
                    child: Text(
                      _previewError!,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12.8,
                        fontWeight: FontWeight.w700,
                        color: c.error,
                      ),
                    ),
                  ),
                ],
                if (_previewSummary != null) ...[
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
                              label: _previewSummary!.wasEncrypted
                                  ? 'Đã giải mã & khớp SHA-256'
                                  : 'Khớp toàn vẹn SHA-256',
                              tone: LifeOsAccentTone.emerald,
                            ),
                            LifeOsStatusPill(
                              label: 'Schema v${_previewSummary!.schemaVersion}',
                              tone: LifeOsAccentTone.blue,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tổng ${_previewSummary!.totalRecordCount} bản ghi (${dateFmt.format(_previewSummary!.exportedAt.toLocal())})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ví: ${_previewSummary!.walletCount} · Giao dịch: ${_previewSummary!.transactionCount} · Ngân sách: ${_previewSummary!.budgetCount} · Lịch: ${_previewSummary!.eventCount} · Việc: ${_previewSummary!.taskCount}',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 12.2,
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
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
                          onChanged: (m) {
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
                            onChanged: (v) => setState(
                              () => _explicitReplaceConfirmed = v ?? false,
                            ),
                            title: Text(
                              'Tôi hiểu chế độ Ghi đè sẽ thay thế bản ghi hiện tại bằng bản sao lưu này',
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
                            onPressed: () => _applyRestore(context),
                            icon: const Icon(Icons.restore_rounded, size: 18),
                            label: const Text('Thực hiện khôi phục'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_lastReport != null) ...[
                  const SizedBox(height: 10),
                  LifeOsSoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in _lastReport!.detailsVi)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• $line',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 12.6,
                                fontWeight: FontWeight.w700,
                                color: c.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
