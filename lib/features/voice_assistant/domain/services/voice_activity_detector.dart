import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Fixed-capacity circular buffer for 16kHz mono PCM16 audio frames with pre-roll preservation.
class Pcm16RingBuffer {
  final int capacitySamples;
  final int preRollSamples;
  final Int16List _buffer;
  int _writeCursor = 0;
  int _length = 0;
  int _totalWrittenSamples = 0;

  Pcm16RingBuffer({
    int sampleRateHz = 16000,
    int preRollMs = 300,
    int? capacitySamples,
  }) : preRollSamples = ((sampleRateHz * preRollMs) ~/ 1000).clamp(1, 480000),
       capacitySamples =
           capacitySamples ??
           math.max((sampleRateHz * 3), ((sampleRateHz * preRollMs) ~/ 1000)),
       _buffer = Int16List(
         capacitySamples ??
             math.max((sampleRateHz * 3), ((sampleRateHz * preRollMs) ~/ 1000)),
       ) {
    if (this.capacitySamples < preRollSamples) {
      throw ArgumentError(
        'capacitySamples ($capacitySamples) must be >= preRollSamples ($preRollSamples)',
      );
    }
  }

  int get length => _length;

  int get totalWrittenSamples => _totalWrittenSamples;

  void writeFrame(List<int> samples) {
    for (final sample in samples) {
      final clamped = sample < -32768
          ? -32768
          : (sample > 32767 ? 32767 : sample);
      _buffer[_writeCursor] = clamped;
      _writeCursor = (_writeCursor + 1) % capacitySamples;
      if (_length < capacitySamples) {
        _length += 1;
      }
      _totalWrittenSamples += 1;
    }
  }

  List<int> readLastSamples(int count) {
    if (count <= 0 || _length == 0) return const <int>[];
    final take = count < _length ? count : _length;
    final out = List<int>.filled(take, 0, growable: false);
    final start = (_writeCursor - take + capacitySamples) % capacitySamples;
    for (var i = 0; i < take; i++) {
      out[i] = _buffer[(start + i) % capacitySamples];
    }
    return out;
  }

  List<int> readPreRoll() => readLastSamples(preRollSamples);

  void clear() {
    _writeCursor = 0;
    _length = 0;
    _totalWrittenSamples = 0;
    _buffer.fillRange(0, _buffer.length, 0);
  }
}

/// Frame-level voice activity classification output.
class VadFrameResult extends Equatable {
  final bool isSpeech;
  final double probability;
  final double energyDbfs;
  final double noiseFloorDbfs;
  final double zeroCrossingRate;
  final int speechDurationMs;
  final int silenceDurationMs;
  final bool isPreRollTriggered;
  final bool isHangoverActive;

  const VadFrameResult({
    required this.isSpeech,
    required this.probability,
    required this.energyDbfs,
    required this.noiseFloorDbfs,
    required this.zeroCrossingRate,
    required this.speechDurationMs,
    required this.silenceDurationMs,
    required this.isPreRollTriggered,
    required this.isHangoverActive,
  });

  @override
  List<Object?> get props => <Object?>[
    isSpeech,
    probability,
    energyDbfs,
    noiseFloorDbfs,
    zeroCrossingRate,
    speechDurationMs,
    silenceDurationMs,
    isPreRollTriggered,
    isHangoverActive,
  ];
}

/// Abstract real-time Voice Activity Detector for PCM16 audio frames.
abstract interface class VoiceActivityDetector {
  VadFrameResult processPcm16Frame(
    List<int> samples, {
    required int sampleRateHz,
    required int monotonicTimestampMs,
  });

  void reset();
}

/// Adaptive RMS dBFS + Zero-Crossing Rate + hangover VAD with bounded pre-roll ring buffer.
class AdaptiveEnergyZcrVad implements VoiceActivityDetector {
  final double speechMarginDb;
  final double minSpeechDbfs;
  final double maxSpeechZcr;
  final double noiseFloorAlpha;
  final int hangoverMs;
  final Pcm16RingBuffer ringBuffer;

  double _noiseFloorDbfs = -58.0;
  bool _noiseFloorInitialized = false;
  bool _inSpeech = false;
  int? _speechStartMs;
  int? _lastSpeechFrameMs;
  int? _silenceStartMs;

  AdaptiveEnergyZcrVad({
    this.speechMarginDb = 8.0,
    this.minSpeechDbfs = -44.0,
    this.maxSpeechZcr = 0.45,
    this.noiseFloorAlpha = 0.08,
    this.hangoverMs = 240,
    Pcm16RingBuffer? ringBuffer,
  }) : ringBuffer = ringBuffer ?? Pcm16RingBuffer();

  double get noiseFloorDbfs => _noiseFloorDbfs;

  @override
  VadFrameResult processPcm16Frame(
    List<int> samples, {
    required int sampleRateHz,
    required int monotonicTimestampMs,
  }) {
    if (samples.isEmpty || sampleRateHz <= 0) {
      return VadFrameResult(
        isSpeech: false,
        probability: 0.0,
        energyDbfs: -120.0,
        noiseFloorDbfs: _noiseFloorDbfs,
        zeroCrossingRate: 0.0,
        speechDurationMs: 0,
        silenceDurationMs: 0,
        isPreRollTriggered: false,
        isHangoverActive: false,
      );
    }

    ringBuffer.writeFrame(samples);

    var sumSquares = 0.0;
    var zeroCrossings = 0;
    var prevSign = samples.first >= 0;

    for (var i = 0; i < samples.length; i++) {
      final norm = samples[i] / 32768.0;
      sumSquares += norm * norm;
      if (i > 0) {
        final curSign = samples[i] >= 0;
        if (curSign != prevSign) {
          zeroCrossings += 1;
        }
        prevSign = curSign;
      }
    }

    final rms = math.sqrt(sumSquares / samples.length);
    final energyDbfs = 20.0 * (math.log(math.max(rms, 1e-6)) / math.ln10);
    final zcr = samples.length > 1 ? zeroCrossings / (samples.length - 1) : 0.0;

    if (!_noiseFloorInitialized) {
      _noiseFloorDbfs = energyDbfs.clamp(-85.0, -32.0);
      _noiseFloorInitialized = true;
    }

    final snrDb = energyDbfs - _noiseFloorDbfs;
    final zcrWithinVoiceBand = zcr <= maxSpeechZcr || snrDb >= 14.0;
    final rawSpeech =
        snrDb >= speechMarginDb &&
        energyDbfs >= minSpeechDbfs &&
        zcrWithinVoiceBand;

    var preRollTriggered = false;
    var hangoverActive = false;
    var isSpeech = rawSpeech;

    if (rawSpeech) {
      if (!_inSpeech) {
        _inSpeech = true;
        preRollTriggered = true;
        _speechStartMs ??= monotonicTimestampMs;
      }
      _lastSpeechFrameMs = monotonicTimestampMs;
      _silenceStartMs = null;
    } else {
      final lastSpeechMs = _lastSpeechFrameMs;
      if (_inSpeech &&
          lastSpeechMs != null &&
          (monotonicTimestampMs - lastSpeechMs) <= hangoverMs) {
        isSpeech = true;
        hangoverActive = true;
      } else {
        _inSpeech = false;
        _silenceStartMs ??= monotonicTimestampMs;
        // Adapt noise floor slowly during non-speech frames.
        final clampedFrame = energyDbfs.clamp(-90.0, -25.0);
        _noiseFloorDbfs =
            (_noiseFloorDbfs * (1.0 - noiseFloorAlpha)) +
            (clampedFrame * noiseFloorAlpha);
      }
    }

    final probRaw = ((snrDb - 2.0) / 18.0).clamp(0.0, 1.0);
    final probability = zcrWithinVoiceBand ? probRaw : probRaw * 0.35;
    final speechDurationMs = _inSpeech && _speechStartMs != null
        ? math.max(0, monotonicTimestampMs - _speechStartMs!)
        : 0;
    final silenceDurationMs = !_inSpeech && _silenceStartMs != null
        ? math.max(0, monotonicTimestampMs - _silenceStartMs!)
        : 0;

    return VadFrameResult(
      isSpeech: isSpeech,
      probability: probability,
      energyDbfs: energyDbfs,
      noiseFloorDbfs: _noiseFloorDbfs,
      zeroCrossingRate: zcr,
      speechDurationMs: speechDurationMs,
      silenceDurationMs: silenceDurationMs,
      isPreRollTriggered: preRollTriggered,
      isHangoverActive: hangoverActive,
    );
  }

  @override
  void reset() {
    ringBuffer.clear();
    _noiseFloorDbfs = -58.0;
    _noiseFloorInitialized = false;
    _inSpeech = false;
    _speechStartMs = null;
    _lastSpeechFrameMs = null;
    _silenceStartMs = null;
  }
}

/// Truthful audio energy sample that NEVER fabricates synthetic speech peaks.
class VoiceWaveformSample extends Equatable {
  final double normalizedLevel;
  final double? rmsDb;
  final bool isRealAudioLevel;
  final bool isIndeterminateActive;
  final int monotonicTimestampMs;

  const VoiceWaveformSample({
    required this.normalizedLevel,
    required this.rmsDb,
    required this.isRealAudioLevel,
    required this.isIndeterminateActive,
    required this.monotonicTimestampMs,
  });

  factory VoiceWaveformSample.silent({int monotonicTimestampMs = 0}) {
    return VoiceWaveformSample(
      normalizedLevel: 0.0,
      rmsDb: null,
      isRealAudioLevel: false,
      isIndeterminateActive: false,
      monotonicTimestampMs: monotonicTimestampMs,
    );
  }

  /// Active listening state when native engine does not emit real RMS callbacks.
  factory VoiceWaveformSample.indeterminateActive({
    required int monotonicTimestampMs,
  }) {
    return VoiceWaveformSample(
      normalizedLevel: 0.0,
      rmsDb: null,
      isRealAudioLevel: false,
      isIndeterminateActive: true,
      monotonicTimestampMs: monotonicTimestampMs,
    );
  }

  /// Real Android SpeechRecognizer RMS dB callback (`-2..10 dB` typical).
  factory VoiceWaveformSample.fromRmsDb(
    double rmsDb, {
    required int monotonicTimestampMs,
  }) {
    final normalized = ((rmsDb + 2.0) / 12.0).clamp(0.0, 1.0);
    return VoiceWaveformSample(
      normalizedLevel: normalized,
      rmsDb: rmsDb,
      isRealAudioLevel: true,
      isIndeterminateActive: false,
      monotonicTimestampMs: monotonicTimestampMs,
    );
  }

  /// Real PCM16 energy in dBFS (`-60..0 dBFS` speech range).
  factory VoiceWaveformSample.fromPcmEnergy(
    double energyDbfs, {
    required int monotonicTimestampMs,
  }) {
    final normalized = ((energyDbfs + 55.0) / 45.0).clamp(0.0, 1.0);
    return VoiceWaveformSample(
      normalizedLevel: normalized,
      rmsDb: energyDbfs,
      isRealAudioLevel: true,
      isIndeterminateActive: false,
      monotonicTimestampMs: monotonicTimestampMs,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    normalizedLevel,
    rmsDb,
    isRealAudioLevel,
    isIndeterminateActive,
    monotonicTimestampMs,
  ];
}
