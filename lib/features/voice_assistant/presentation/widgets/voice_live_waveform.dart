import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/voice_session.dart';
import '../../domain/services/voice_activity_detector.dart';

/// Truthful Voice Engine 2.0 live waveform indicator.
///
/// Strictly separates:
/// - Real audio energy (`VoiceWaveformSample.isRealAudioLevel == true`): plots a rolling
///   bar history directly from real PCM16 energy or valid RMS callbacks.
/// - Indeterminate listening (`isIndeterminateActive == true`): renders an honest flat
///   active baseline with clear text rather than fabricating fake speech peaks!
class VoiceLiveWaveform extends StatefulWidget {
  final VoiceWaveformSample sample;
  final VoiceSessionPhase phase;
  final Color? accentColor;
  final double height;

  const VoiceLiveWaveform({
    super.key,
    required this.sample,
    required this.phase,
    this.accentColor,
    this.height = 38,
  });

  @override
  State<VoiceLiveWaveform> createState() => _VoiceLiveWaveformState();
}

class _VoiceLiveWaveformState extends State<VoiceLiveWaveform> {
  static const int _barCount = 18;
  final List<double> _history = List<double>.filled(
    _barCount,
    0.0,
    growable: true,
  );

  @override
  void didUpdateWidget(covariant VoiceLiveWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isActive =
        widget.phase == VoiceSessionPhase.listening ||
        widget.phase == VoiceSessionPhase.preparing ||
        widget.phase == VoiceSessionPhase.finalizing;

    if (!isActive) {
      for (var i = 0; i < _history.length; i++) {
        _history[i] = 0.0;
      }
      return;
    }

    if (widget.sample.isRealAudioLevel &&
        widget.sample.monotonicTimestampMs !=
            oldWidget.sample.monotonicTimestampMs) {
      _history.removeAt(0);
      _history.add(widget.sample.normalizedLevel.clamp(0.0, 1.0));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = TammySemanticColors.of(context);
    final accent = widget.accentColor ?? palette.primary;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final isListening = widget.phase == VoiceSessionPhase.listening;
    final isPreparing = widget.phase == VoiceSessionPhase.preparing;
    final isFinalizing = widget.phase == VoiceSessionPhase.finalizing;
    final hasRealSignal = isListening && widget.sample.isRealAudioLevel;

    final semanticStatus = hasRealSignal
        ? 'Mức âm thanh thực ${(widget.sample.normalizedLevel * 100).round()} phần trăm'
        : isListening
        ? 'Đang nghe tiếng Việt — thiết bị không cung cấp mức âm lượng trực tiếp'
        : isFinalizing
        ? 'Đang hoàn tất câu nói'
        : isPreparing
        ? 'Đang mở micro'
        : 'Micro đang nghỉ';

    return Semantics(
      label: semanticStatus,
      liveRegion: false,
      child: RepaintBoundary(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: widget.height,
              child: CustomPaint(
                painter: _TruthfulWaveformPainter(
                  history: List<double>.unmodifiable(_history),
                  hasRealSignal: hasRealSignal,
                  isIndeterminateListening:
                      isListening && !hasRealSignal && !disableAnim,
                  isActivePhase: isListening || isPreparing || isFinalizing,
                  accentColor: accent,
                  idleColor: palette.border,
                ),
                size: Size(double.infinity, widget.height),
              ),
            ),
            if (isListening && !hasRealSignal)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Đang lắng nghe (thiết bị không báo mức âm lượng từng khung)',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TruthfulWaveformPainter extends CustomPainter {
  final List<double> history;
  final bool hasRealSignal;
  final bool isIndeterminateListening;
  final bool isActivePhase;
  final Color accentColor;
  final Color idleColor;

  const _TruthfulWaveformPainter({
    required this.history,
    required this.hasRealSignal,
    required this.isIndeterminateListening,
    required this.isActivePhase,
    required this.accentColor,
    required this.idleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final count = history.length;
    if (count == 0 || size.width <= 0 || size.height <= 0) return;

    final slotWidth = size.width / count;
    final barWidth = (slotWidth * 0.56).clamp(2.5, 6.0);
    final centerY = size.height / 2;

    for (var i = 0; i < count; i++) {
      final x = (i + 0.5) * slotWidth;
      final double barHeight;
      final Color barColor;

      if (hasRealSignal) {
        final amp = history[i].clamp(0.0, 1.0);
        barHeight = (4.0 + amp * (size.height - 6.0)).clamp(4.0, size.height);
        barColor = accentColor.withValues(alpha: 0.35 + amp * 0.65);
      } else if (isActivePhase) {
        // Honest flat baseline — NEVER fabricates synthetic speech spikes!
        barHeight = isIndeterminateListening ? 6.0 : 4.0;
        barColor = accentColor.withValues(alpha: 0.45);
      } else {
        barHeight = 3.0;
        barColor = idleColor.withValues(alpha: 0.65);
      }

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: barWidth,
          height: barHeight,
        ),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, Paint()..color = barColor);
    }
  }

  @override
  bool shouldRepaint(covariant _TruthfulWaveformPainter oldDelegate) {
    if (hasRealSignal != oldDelegate.hasRealSignal ||
        isIndeterminateListening != oldDelegate.isIndeterminateListening ||
        isActivePhase != oldDelegate.isActivePhase ||
        accentColor != oldDelegate.accentColor) {
      return true;
    }
    if (history.length != oldDelegate.history.length) return true;
    for (var i = 0; i < history.length; i++) {
      if ((history[i] - oldDelegate.history[i]).abs() > 0.01) {
        return true;
      }
    }
    return false;
  }
}
