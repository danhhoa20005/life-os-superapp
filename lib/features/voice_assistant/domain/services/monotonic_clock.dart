import 'dart:async';

/// Monotonic clock for deterministic duration/timeout calculations and TTL audits.
abstract interface class MonotonicClock {
  /// Monotonically non-decreasing elapsed milliseconds (immune to wall-clock jumps).
  int get elapsedMilliseconds;

  /// Wall-clock timestamp strictly for capability cache TTL / audit metadata.
  DateTime get wallNow;
}

/// Production clock backed by Dart's monotonic [Stopwatch].
class SystemMonotonicClock implements MonotonicClock {
  final Stopwatch _stopwatch = Stopwatch()..start();

  SystemMonotonicClock();

  @override
  int get elapsedMilliseconds => _stopwatch.elapsedMilliseconds;

  @override
  DateTime get wallNow => DateTime.now();
}

/// Deterministic clock for unit tests supporting explicit time advances and wall jumps.
class FakeMonotonicClock implements MonotonicClock {
  int _elapsedMs;
  DateTime _wallNow;

  FakeMonotonicClock({int initialElapsedMs = 0, DateTime? initialWallNow})
    : _elapsedMs = initialElapsedMs,
      _wallNow = initialWallNow ?? DateTime.utc(2026, 11, 25, 12, 0, 0);

  @override
  int get elapsedMilliseconds => _elapsedMs;

  @override
  DateTime get wallNow => _wallNow;

  void advance(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms < 0) {
      throw ArgumentError.value(duration, 'duration', 'Cannot go backwards');
    }
    _elapsedMs += ms;
    _wallNow = _wallNow.add(duration);
  }

  /// Simulates an NTP/timezone wall-clock jump without altering monotonic elapsed time.
  void jumpWallClock(Duration delta) {
    _wallNow = _wallNow.add(delta);
  }
}

/// Cancellable timer handle created by [VoiceTimerFactory].
abstract interface class VoiceTimerHandle {
  bool get isActive;
  void cancel();
}

/// Abstract timer factory so coordinator timeouts run deterministically in tests.
abstract interface class VoiceTimerFactory {
  VoiceTimerHandle createTimer(Duration duration, void Function() callback);
}

class _RealVoiceTimerHandle implements VoiceTimerHandle {
  final Timer _timer;
  bool _active = true;

  _RealVoiceTimerHandle(Duration duration, void Function() callback)
    : _timer = Timer(duration, callback);

  @override
  bool get isActive => _active && _timer.isActive;

  @override
  void cancel() {
    _active = false;
    _timer.cancel();
  }
}

/// Production timer factory delegating to `dart:async` [Timer].
class RealVoiceTimerFactory implements VoiceTimerFactory {
  const RealVoiceTimerFactory();

  @override
  VoiceTimerHandle createTimer(Duration duration, void Function() callback) {
    late _RealVoiceTimerHandle handle;
    handle = _RealVoiceTimerHandle(duration, () {
      handle._active = false;
      callback();
    });
    return handle;
  }
}

class _ScheduledFakeTimer implements VoiceTimerHandle {
  final int id;
  final int fireAtMs;
  final void Function() callback;
  bool cancelled = false;
  bool fired = false;

  _ScheduledFakeTimer({
    required this.id,
    required this.fireAtMs,
    required this.callback,
  });

  @override
  bool get isActive => !cancelled && !fired;

  @override
  void cancel() {
    cancelled = true;
  }
}

/// Deterministic virtual-time timer scheduler synced with [FakeMonotonicClock].
class FakeVoiceTimerFactory implements VoiceTimerFactory {
  final FakeMonotonicClock clock;
  final List<_ScheduledFakeTimer> _timers = <_ScheduledFakeTimer>[];
  int _nextId = 1;

  FakeVoiceTimerFactory(this.clock);

  int get activeTimerCount => _timers.where((t) => t.isActive).length;

  @override
  VoiceTimerHandle createTimer(Duration duration, void Function() callback) {
    final delayMs = duration.inMilliseconds < 0 ? 0 : duration.inMilliseconds;
    final entry = _ScheduledFakeTimer(
      id: _nextId++,
      fireAtMs: clock.elapsedMilliseconds + delayMs,
      callback: callback,
    );
    _timers.add(entry);
    return entry;
  }

  /// Advances [clock] by [duration], firing due timers in chronological order.
  void advance(Duration duration) {
    final totalMs = duration.inMilliseconds;
    if (totalMs < 0) {
      throw ArgumentError.value(duration, 'duration', 'Cannot go backwards');
    }
    final targetMs = clock.elapsedMilliseconds + totalMs;

    while (true) {
      _ScheduledFakeTimer? nextDue;
      for (final t in _timers) {
        if (!t.isActive || t.fireAtMs > targetMs) continue;
        if (nextDue == null ||
            t.fireAtMs < nextDue.fireAtMs ||
            (t.fireAtMs == nextDue.fireAtMs && t.id < nextDue.id)) {
          nextDue = t;
        }
      }
      if (nextDue == null) break;

      final deltaMs = nextDue.fireAtMs - clock.elapsedMilliseconds;
      if (deltaMs > 0) {
        clock.advance(Duration(milliseconds: deltaMs));
      }
      nextDue.fired = true;
      nextDue.callback();
    }

    final remainingMs = targetMs - clock.elapsedMilliseconds;
    if (remainingMs > 0) {
      clock.advance(Duration(milliseconds: remainingMs));
    }
    _timers.removeWhere((t) => !t.isActive);
  }
}
