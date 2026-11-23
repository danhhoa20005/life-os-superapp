import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../constants/app_assets.dart';
import '../utils/vietqr_emv_builder.dart';
import '../utils/vnd_amount.dart';
import 'lifeos_top_toast.dart';
import 'status_widgets.dart';

const List<({String bin, String shortName, String fullName})> kVietQrBanks = kLifeOsVietQrBanks;

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
    final def = context.read<NotificationIngestionBloc>().state.defaultBankAccount;
    if (def != null) {
      prefilled = (bin: def.bankBin, acc: def.accountNumber, holder: def.accountHolderName);
    }
  } catch (_) {}

  var selectedBin = prefilled?.bin ?? kLifeOsVietQrBanks.first.bin;
  final accCtrl = TextEditingController(text: prefilled?.acc ?? '');

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final c = TammySemanticColors.of(ctx);
          final accNumber = accCtrl.text.trim();
          final hasValidAcc = accNumber.length >= 6;
          final emvPayload = hasValidAcc
              ? VietQrEmvBuilder.buildNapas247Payload(
                  bankBin: selectedBin,
                  accountNumber: accNumber,
                  amountVnd: amountMinor,
                  memo: sePayCode,
                )
              : null;
          final vietQrUrl = hasValidAcc
              ? VietQrEmvBuilder.buildVisualQrUrl(
                  bankBin: selectedBin,
                  accountNumber: accNumber,
                  accountHolderName: prefilled?.holder ?? toName,
                  amountVnd: amountMinor,
                  memo: sePayCode,
                )
              : null;

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
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
                                style: Theme.of(ctx).textTheme.titleMedium,
                              ),
                              Text(
                                '$fromName chuyển trả $toName',
                                style: Theme.of(ctx).textTheme.bodySmall,
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
                            VndAmount.format(amountMinor),
                            style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(
                                  color: c.primary,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: sePayCode));
                              LifeOsTopToast.show(
                                ctx,
                                'Đã sao chép nội dung: $sePayCode',
                                kind: LifeOsToastKind.success,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy_rounded, size: 14, color: c.secondary),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      sePayCode,
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
                            initialValue: selectedBin,
                            decoration: const InputDecoration(
                              labelText: 'Ngân hàng nhận',
                              isDense: true,
                            ),
                            items: kLifeOsVietQrBanks
                                .map(
                                  (b) => DropdownMenuItem(
                                    value: b.bin,
                                    child: Text(
                                      '${b.shortName} · ${b.fullName}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setModalState(() => selectedBin = v);
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          flex: 6,
                          child: TextField(
                            controller: accCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setModalState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Số tài khoản người nhận',
                              hintText: 'Nhập STK nhận tiền',
                              isDense: true,
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
                                    emvPayload ?? sePayCode,
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
                      label: 'Giữ nguyên mã nội dung để ứng dụng tự động gạch nợ khi nhận tiền',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        onConfirmSettled();
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Xác nhận đã chuyển khoản'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
  accCtrl.dispose();
}

typedef LinkedBankAccountStateSnapshot = ({String bin, String acc, String holder});
