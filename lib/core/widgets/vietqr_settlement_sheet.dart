import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../constants/app_assets.dart';
import '../utils/vietnamese_search_matcher.dart';
import '../utils/vietqr_emv_builder.dart';
import '../utils/vnd_amount.dart';
import 'lifeos_top_toast.dart';
import 'status_widgets.dart';

const List<({String bin, String shortName, String fullName})> kVietQrBanks =
    kLifeOsVietQrBanks;

Future<void> showVietQrSettlementSheet({
  required BuildContext context,
  required String fromName,
  required String toName,
  required int amountMinor,
  required String sePayCode,
  required VoidCallback onConfirmSettled,
}) async {
  LinkedBankAccountStateSnapshot? prefilled;
  try {
    final def =
        context.read<NotificationIngestionBloc>().state.defaultBankAccount;
    if (def != null) {
      final foldedTo = VietnameseSearchMatcher.fold(toName);
      final foldedHolder = VietnameseSearchMatcher.fold(def.accountHolderName);
      if (foldedTo.isEmpty ||
          foldedTo == 'toi' ||
          (foldedHolder.isNotEmpty &&
              (foldedTo.contains(foldedHolder) ||
                  foldedHolder.contains(foldedTo)))) {
        prefilled = (
          bin: def.bankBin,
          acc: def.accountNumber,
          holder: def.accountHolderName,
        );
      }
    }
  } catch (_) {}

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) => _VietQrSettlementSheetBody(
      fromName: fromName,
      toName: toName,
      amountMinor: amountMinor,
      sePayCode: sePayCode,
      prefilled: prefilled,
      onConfirmSettled: onConfirmSettled,
    ),
  );
}

class _VietQrSettlementSheetBody extends StatefulWidget {
  final String fromName;
  final String toName;
  final int amountMinor;
  final String sePayCode;
  final LinkedBankAccountStateSnapshot? prefilled;
  final VoidCallback onConfirmSettled;

  const _VietQrSettlementSheetBody({
    required this.fromName,
    required this.toName,
    required this.amountMinor,
    required this.sePayCode,
    required this.prefilled,
    required this.onConfirmSettled,
  });

  @override
  State<_VietQrSettlementSheetBody> createState() =>
      _VietQrSettlementSheetBodyState();
}

class _VietQrSettlementSheetBodyState
    extends State<_VietQrSettlementSheetBody> {
  late String _selectedBin;
  late final TextEditingController _accCtrl;

  @override
  void initState() {
    super.initState();
    final candidateBin = widget.prefilled?.bin ?? '';
    final isListedBin = kLifeOsVietQrBanks.any((b) => b.bin == candidateBin);
    _selectedBin = isListedBin ? candidateBin : kLifeOsVietQrBanks.first.bin;
    _accCtrl = TextEditingController(text: widget.prefilled?.acc ?? '');
  }

  @override
  void dispose() {
    _accCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final accNumber = _accCtrl.text.trim();
    final hasValidAcc = accNumber.length >= 6;
    final matchesPrefilled =
        widget.prefilled != null &&
        accNumber == widget.prefilled!.acc &&
        _selectedBin == widget.prefilled!.bin;
    final resolvedHolder = matchesPrefilled
        ? widget.prefilled!.holder
        : widget.toName;

    final emvPayload = hasValidAcc
        ? VietQrEmvBuilder.buildNapas247Payload(
            bankBin: _selectedBin,
            accountNumber: accNumber,
            amountVnd: widget.amountMinor,
            memo: widget.sePayCode,
          )
        : null;
    final vietQrUrl = hasValidAcc
        ? VietQrEmvBuilder.buildVisualQrUrl(
            bankBin: _selectedBin,
            accountNumber: accNumber,
            accountHolderName: resolvedHolder,
            amountVnd: widget.amountMinor,
            memo: widget.sePayCode,
          )
        : null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  BananaGlassIcon(
                    assetPath: AppAssets.icSysVietQr,
                    fallbackIcon: Icons.qr_code_2_rounded,
                    fallbackColor: c.primary,
                    size: 42,
                    borderRadius: 12,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mã QR Thanh Toán Nhóm',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${widget.fromName} chuyển trả ${widget.toName}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.separator),
                ),
                child: Column(
                  children: [
                    Text(
                      VndAmount.format(widget.amountMinor),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: c.primary,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: widget.sePayCode),
                        );
                        LifeOsTopToast.show(
                          context,
                          'Đã sao chép nội dung: ${widget.sePayCode}',
                          kind: LifeOsToastKind.success,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.copy_rounded,
                              size: 14,
                              color: c.secondary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                widget.sePayCode,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                  color: c.secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedBin,
                      decoration: const InputDecoration(
                        labelText: 'Ngân hàng nhận',
                        isDense: true,
                      ),
                      items: kLifeOsVietQrBanks
                          .map(
                            (b) => DropdownMenuItem(
                              value: b.bin,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text('${b.shortName} · ${b.fullName}'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedBin = v);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 6,
                    child: TextField(
                      controller: _accCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Số tài khoản người nhận',
                        hintText: 'Nhập STK nhận tiền',
                        isDense: true,
                        suffixIcon: _accCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Xóa số tài khoản',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() {
                                  _accCtrl.clear();
                                }),
                                icon: const Icon(Icons.close_rounded, size: 17),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Container(
                  width: 220,
                  height: 220,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.separator),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: vietQrUrl != null
                      ? Image.network(
                          vietQrUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Center(
                            child: SelectableText(
                              emvPayload ?? widget.sePayCode,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontFamily: 'monospace',
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        )
                      : const Center(
                          child: Text(
                            'Nhập số tài khoản người nhận ở trên để hiển thị mã VietQR.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF475467),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const SemanticStatusBadge(
                kind: SemanticStatusKind.info,
                label:
                    'Giữ nguyên mã nội dung để ứng dụng tự động gạch nợ khi nhận tiền',
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: widget.amountMinor <= 0
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        widget.onConfirmSettled();
                      },
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Xác nhận đã chuyển khoản'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef LinkedBankAccountStateSnapshot = ({
  String bin,
  String acc,
  String holder,
});
