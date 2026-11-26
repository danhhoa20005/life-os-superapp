import 'package:flutter/material.dart';

import '../utils/qr_matrix_encoder.dart';

/// Pure on-device EMVCo / VietQR matrix renderer with zero external HTTP calls.
///
/// Guarantees bank account numbers, holder names, amounts, and payment memos
/// never leave the user's device when displaying a collection QR code.
class OfflineVietQrView extends StatelessWidget {
  final String payload;
  final String paymentCode;
  final double size;

  const OfflineVietQrView({
    super.key,
    required this.payload,
    required this.paymentCode,
    this.size = 200,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) {
      return _buildFallback();
    }
    try {
      final matrix = QrMatrixEncoder.encode(trimmed);
      return Semantics(
        label: 'Mã QR thu tiền nội bộ trên thiết bị ($paymentCode)',
        image: true,
        child: CustomPaint(
          key: const Key('offline_vietqr_canvas'),
          size: Size.square(size),
          painter: _QrMatrixPainter(matrix),
        ),
      );
    } catch (_) {
      return _buildFallback();
    }
  }

  Widget _buildFallback() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.qr_code_2_rounded, size: 54, color: Colors.black54),
          const SizedBox(height: 6),
          Text(
            paymentCode,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _QrMatrixPainter extends CustomPainter {
  final QrMatrix matrix;

  const _QrMatrixPainter(this.matrix);

  @override
  void paint(Canvas canvas, Size size) {
    const quietZone = 2;
    final totalModules = matrix.size + quietZone * 2;
    final cellSize = size.shortestSide / totalModules;
    final darkPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;

    for (var r = 0; r < matrix.size; r++) {
      for (var c = 0; c < matrix.size; c++) {
        if (matrix.isDark(r, c)) {
          final left = (c + quietZone) * cellSize;
          final top = (r + quietZone) * cellSize;
          canvas.drawRect(
            Rect.fromLTWH(left, top, cellSize + 0.15, cellSize + 0.15),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrMatrixPainter oldDelegate) =>
      oldDelegate.matrix.version != matrix.version ||
      oldDelegate.matrix.size != matrix.size;
}
