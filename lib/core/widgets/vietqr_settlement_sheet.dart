import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../constants/app_assets.dart';
import '../utils/vnd_amount.dart';
import 'status_widgets.dart';

const List<({String bin, String shortName, String fullName})> kVietQrBanks = [
  (bin: '970436', shortName: 'VCB', fullName: 'Vietcombank'),
  (bin: '970422', shortName: 'MB', fullName: 'MB Bank'),
  (bin: '970407', shortName: 'TCB', fullName: 'Techcombank'),
  (bin: '970418', shortName: 'BIDV', fullName: 'BIDV'),
  (bin: '970415', shortName: 'ICB', fullName: 'VietinBank'),
  (bin: '970416', shortName: 'ACB', fullName: 'ACB'),
  (bin: '970432', shortName: 'VPB', fullName: 'VPBank'),
  (bin: '970423', shortName: 'TPB', fullName: 'TPBank'),
];

Future<void> showVietQrSettlementSheet({
  required BuildContext context,
  required String fromName,
  required String toName,
  required int amountMinor,
  required String sePayCode,
  required VoidCallback onConfirmSettled,
}) async {
  var selectedBin = kVietQrBanks.first.bin;
  final accCtrl = TextEditingController();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final c = TammySemanticColors.of(ctx);
          final accNumber = accCtrl.text.trim();
          final encodedMemo = Uri.encodeComponent(sePayCode);
          final encodedName = Uri.encodeComponent(toName);
          final vietQrUrl = accNumber.length >= 6
              ? 'https://img.vietqr.io/image/$selectedBin-$accNumber-compact2.png?amount=$amountMinor&addInfo=$encodedMemo&accountName=$encodedName'
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
                                'Mã QR Quyết toán Nhóm · VietQR / SePay',
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
                              LifeOsTopToast.fromSnackBar(ctx, 
                                SnackBar(content: Text('✓ Đã sao chép nội dung: $sePayCode')),
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
                            items: kVietQrBanks
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
                              hintText: 'Nhập STK để tạo VietQR',
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
                                errorBuilder: (_, __, ___) => _DeterministicQrPainterWidget(
                                  seedData: '$selectedBin|$accNumber|$amountMinor|$sePayCode',
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: _DeterministicQrPainterWidget(
                                      seedData: '$amountMinor|$sePayCode',
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Nhập STK bên trên để sinh ảnh VietQR chuẩn NAPAS 247',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF475467),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const SemanticStatusBadge(
                      kind: SemanticStatusKind.info,
                      label:
                          'Mẹo: Giữ nguyên nội dung SEVQR LIFEOS để hệ thống tự động đối soát 100%',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        onConfirmSettled();
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Xác nhận đã chuyển khoản thanh toán'),
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

class _DeterministicQrPainterWidget extends StatelessWidget {
  final String seedData;

  const _DeterministicQrPainterWidget({required this.seedData});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _GeometricMatrixPainter(seedData),
        ),
      ),
    );
  }
}

class _GeometricMatrixPainter extends CustomPainter {
  final String seed;

  const _GeometricMatrixPainter(this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    const grid = 21;
    final cell = size.width / grid;
    final darkPaint = Paint()
      ..color = const Color(0xFF0B3B2E)
      ..style = PaintingStyle.fill;

    void drawFinder(int ox, int oy) {
      for (var y = 0; y < 7; y++) {
        for (var x = 0; x < 7; x++) {
          final isOuter = x == 0 || x == 6 || y == 0 || y == 6;
          final isInner = x >= 2 && x <= 4 && y >= 2 && y <= 4;
          if (isOuter || isInner) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH((ox + x) * cell, (oy + y) * cell, cell * 0.92, cell * 0.92),
                Radius.circular(cell * 0.2),
              ),
              darkPaint,
            );
          }
        }
      }
    }

    drawFinder(0, 0);
    drawFinder(grid - 7, 0);
    drawFinder(0, grid - 7);

    var hash = 2166136261;
    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7FFFFFFF;
    }

    for (var y = 0; y < grid; y++) {
      for (var x = 0; x < grid; x++) {
        final inTopLeft = x < 8 && y < 8;
        final inTopRight = x >= grid - 8 && y < 8;
        final inBottomLeft = x < 8 && y >= grid - 8;
        if (inTopLeft || inTopRight || inBottomLeft) continue;

        final bit = ((hash >> ((x * 7 + y * 13) % 28)) ^ (x * 31 + y * 17)) & 1;
        if (bit == 1) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x * cell, y * cell, cell * 0.86, cell * 0.86),
              Radius.circular(cell * 0.2),
            ),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GeometricMatrixPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
