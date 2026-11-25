import 'dart:convert';

import '../services/native_secure_vault_bridge.dart';
import 'behavior_domain.dart';

/// Account-partitioned encrypted local store for Behavior Engine 2.0 state,
/// bounded anonymized event history, and local UX quality counters.
/// Never transmits behavioral telemetry over the network.
class LocalBehaviorStore {
  static const String _keySettings = 'ux_behavior_settings_v2';
  static const String _keyEvents = 'ux_behavior_events_v2';
  static const String _keyMetrics = 'ux_ux_metrics_v2';
  static const int maxRollingEvents = 200;

  static final LocalBehaviorStore instance = LocalBehaviorStore();

  final NativeSecureVaultBridge _vault;
  final Set<String> _trackedKeys = <String>{};

  String? _activeUserId;
  PersonalizationSettings? _cachedSettings;
  List<BehaviorEvent>? _cachedEvents;
  UxMetricsSnapshot? _cachedMetrics;

  LocalBehaviorStore({NativeSecureVaultBridge? vault})
    : _vault = vault ?? NativeSecureVaultBridge.instance;

  String? get activeUserId => _activeUserId;

  String _scopedKey(String baseKey) {
    final uid = (_activeUserId ?? '').trim();
    final scoped = '${baseKey}__u_${uid.isEmpty ? 'guest' : uid}';
    _trackedKeys.add(scoped);
    return scoped;
  }

  /// Strictly binds local storage to [userId] and clears in-memory caches so
  /// settings, event streams, and metrics never leak across accounts.
  void bindActiveUser(String? userId) {
    final cleaned = (userId ?? '').trim();
    final nextId = cleaned.isEmpty ? null : cleaned;
    if (_activeUserId == nextId) return;
    _activeUserId = nextId;
    _cachedSettings = null;
    _cachedEvents = null;
    _cachedMetrics = null;
  }

  /// Immediately wipes in-memory caches when the active account signs out.
  void clearSessionOnSignOut() {
    _activeUserId = null;
    _cachedSettings = null;
    _cachedEvents = null;
    _cachedMetrics = null;
  }

  Future<PersonalizationSettings> loadSettings() async {
    if (_cachedSettings != null) return _cachedSettings!;
    final raw = await _vault.readSecret(_scopedKey(_keySettings));
    if (raw == null || raw.trim().isEmpty) {
      _cachedSettings = const PersonalizationSettings();
      return _cachedSettings!;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _cachedSettings = PersonalizationSettings.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        return _cachedSettings!;
      }
    } catch (_) {
      // Fallback to safe defaults if local payload is malformed
    }
    _cachedSettings = const PersonalizationSettings();
    return _cachedSettings!;
  }

  Future<void> saveSettings(PersonalizationSettings settings) async {
    _cachedSettings = settings;
    await _vault.writeSecret(
      key: _scopedKey(_keySettings),
      value: jsonEncode(settings.toJson()),
    );
  }

  Future<List<BehaviorEvent>> loadEvents() async {
    if (_cachedEvents != null) return _cachedEvents!;
    final raw = await _vault.readSecret(_scopedKey(_keyEvents));
    if (raw == null || raw.trim().isEmpty) {
      _cachedEvents = const <BehaviorEvent>[];
      return _cachedEvents!;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final parsed = decoded
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => BehaviorEvent.fromJson(Map<String, dynamic>.from(m)))
            .whereType<BehaviorEvent>()
            .toList(growable: false);
        final trimmed = parsed.length > maxRollingEvents
            ? parsed.sublist(parsed.length - maxRollingEvents)
            : parsed;
        _cachedEvents = List<BehaviorEvent>.unmodifiable(trimmed);
        return _cachedEvents!;
      }
    } catch (_) {
      // Ignore malformed cache safely
    }
    _cachedEvents = const <BehaviorEvent>[];
    return _cachedEvents!;
  }

  Future<void> saveEvents(List<BehaviorEvent> events) async {
    final trimmed = events.length > maxRollingEvents
        ? events.sublist(events.length - maxRollingEvents)
        : events;
    _cachedEvents = List<BehaviorEvent>.unmodifiable(trimmed);
    await _vault.writeSecret(
      key: _scopedKey(_keyEvents),
      value: jsonEncode(_cachedEvents!.map((e) => e.toJson()).toList()),
    );
  }

  Future<UxMetricsSnapshot> loadMetrics() async {
    if (_cachedMetrics != null) return _cachedMetrics!;
    final raw = await _vault.readSecret(_scopedKey(_keyMetrics));
    if (raw == null || raw.trim().isEmpty) {
      _cachedMetrics = UxMetricsSnapshot.empty;
      return _cachedMetrics!;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _cachedMetrics = UxMetricsSnapshot.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        return _cachedMetrics!;
      }
    } catch (_) {
      // Safe default
    }
    _cachedMetrics = UxMetricsSnapshot.empty;
    return _cachedMetrics!;
  }

  Future<void> saveMetrics(UxMetricsSnapshot metrics) async {
    _cachedMetrics = metrics;
    await _vault.writeSecret(
      key: _scopedKey(_keyMetrics),
      value: jsonEncode(metrics.toJson()),
    );
  }

  /// Clears ONLY the active user's behavior settings, events, and UX metrics.
  /// Other accounts partitioned under different `__u_<uid>` keys remain untouched.
  Future<void> resetAllForActiveUser() async {
    _cachedSettings = const PersonalizationSettings();
    _cachedEvents = const <BehaviorEvent>[];
    _cachedMetrics = UxMetricsSnapshot.empty;
    await _vault.deleteSecret(_scopedKey(_keySettings));
    await _vault.deleteSecret(_scopedKey(_keyEvents));
    await _vault.deleteSecret(_scopedKey(_keyMetrics));
  }

  /// Test helper clearing all keys created by this store instance.
  Future<void> resetForTest() async {
    _activeUserId = null;
    _cachedSettings = null;
    _cachedEvents = null;
    _cachedMetrics = null;
    for (final key in _trackedKeys.toList()) {
      await _vault.deleteSecret(key);
    }
    _trackedKeys.clear();
  }
}

/// Records anonymized UX behavior events locally when personalization & consent are enabled.
class BehaviorEventCollector {
  final LocalBehaviorStore _store;

  BehaviorEventCollector({LocalBehaviorStore? store})
    : _store = store ?? LocalBehaviorStore.instance;

  Future<bool> record(BehaviorEvent event) async {
    final settings = await _store.loadSettings();
    if (!settings.enabled || !settings.consentGranted) {
      return false;
    }

    final sanitizedEvent = BehaviorEvent(
      type: event.type,
      timestampEpochMs: event.timestampEpochMs,
      metadata: BehaviorPrivacyPolicy.sanitizeMetadata(event.metadata),
    );

    final currentEvents = await _store.loadEvents();
    final updated = <BehaviorEvent>[...currentEvents, sanitizedEvent];
    final bounded = updated.length > LocalBehaviorStore.maxRollingEvents
        ? updated.sublist(updated.length - LocalBehaviorStore.maxRollingEvents)
        : updated;

    await _store.saveEvents(bounded);
    await _store.saveSettings(
      settings.copyWith(
        totalRecordedSignals: settings.totalRecordedSignals + 1,
      ),
    );
    return true;
  }

  Future<bool> recordType(
    BehaviorEventType type, {
    Map<String, Object?> metadata = const <String, Object?>{},
    DateTime? timestamp,
  }) {
    return record(
      BehaviorEvent.create(
        type: type,
        timestamp: timestamp,
        metadata: metadata,
      ),
    );
  }
}

/// Captures explicit accept/dismiss feedback on contextual recommendations so
/// dismissed items drop priority immediately without nagging.
class FeedbackEngine {
  final LocalBehaviorStore _store;
  final BehaviorEventCollector _collector;
  final UxMetricsTracker _metricsTracker;

  FeedbackEngine({
    LocalBehaviorStore? store,
    BehaviorEventCollector? collector,
    UxMetricsTracker? metricsTracker,
  }) : _store = store ?? LocalBehaviorStore.instance,
       _collector =
           collector ??
           BehaviorEventCollector(store: store ?? LocalBehaviorStore.instance),
       _metricsTracker =
           metricsTracker ??
           UxMetricsTracker(store: store ?? LocalBehaviorStore.instance);

  Future<PersonalizationSettings> recordRecommendationAccepted(
    String recommendationId, {
    String? featureKey,
    DateTime? now,
  }) async {
    final refNow = now ?? DateTime.now();
    final settings = await _store.loadSettings();

    final nextCounts = Map<String, int>.from(settings.dismissedCounts)
      ..remove(recommendationId);
    final nextTimestamps = Map<String, int>.from(settings.lastDismissedEpochMs)
      ..remove(recommendationId);
    if (featureKey != null && featureKey.isNotEmpty) {
      nextCounts.remove(featureKey);
      nextTimestamps.remove(featureKey);
    }

    final updated = settings.copyWith(
      dismissedCounts: Map<String, int>.unmodifiable(nextCounts),
      lastDismissedEpochMs: Map<String, int>.unmodifiable(nextTimestamps),
    );
    await _store.saveSettings(updated);
    await _metricsTracker.recordRecommendationAccepted();

    final recorded = await _collector.recordType(
      BehaviorEventType.recommendationAccepted,
      timestamp: refNow,
      metadata: <String, Object?>{
        'targetId': recommendationId,
        if (featureKey != null && featureKey.isNotEmpty)
          'featureKey': featureKey,
        'hourOfDay': refNow.hour,
        'weekday': refNow.weekday,
      },
    );
    if (recorded) {
      return _store.loadSettings();
    }
    return updated;
  }

  Future<PersonalizationSettings> recordRecommendationDismissed(
    String recommendationId, {
    String? featureKey,
    DateTime? now,
  }) async {
    final refNow = now ?? DateTime.now();
    final settings = await _store.loadSettings();

    final nextCounts = Map<String, int>.from(settings.dismissedCounts);
    nextCounts[recommendationId] = (nextCounts[recommendationId] ?? 0) + 1;

    final nextTimestamps = Map<String, int>.from(settings.lastDismissedEpochMs);
    nextTimestamps[recommendationId] = refNow.millisecondsSinceEpoch;

    final updated = settings.copyWith(
      dismissedCounts: Map<String, int>.unmodifiable(nextCounts),
      lastDismissedEpochMs: Map<String, int>.unmodifiable(nextTimestamps),
    );
    await _store.saveSettings(updated);
    await _metricsTracker.recordRecommendationDismissed();

    final recorded = await _collector.recordType(
      BehaviorEventType.recommendationDismissed,
      timestamp: refNow,
      metadata: <String, Object?>{
        'targetId': recommendationId,
        if (featureKey != null && featureKey.isNotEmpty)
          'featureKey': featureKey,
        'hourOfDay': refNow.hour,
        'weekday': refNow.weekday,
      },
    );
    if (recorded) {
      return _store.loadSettings();
    }
    return updated;
  }
}

/// Opt-in, local-only aggregated UX counters with explicit schema version & reset.
class UxMetricsTracker {
  final LocalBehaviorStore _store;

  UxMetricsTracker({LocalBehaviorStore? store})
    : _store = store ?? LocalBehaviorStore.instance;

  Future<UxMetricsSnapshot> load() => _store.loadMetrics();

  Future<UxMetricsSnapshot> _increment(
    UxMetricsSnapshot Function(UxMetricsSnapshot current) transform,
  ) async {
    final settings = await _store.loadSettings();
    if (!settings.enabled || !settings.consentGranted) {
      return _store.loadMetrics();
    }
    final current = await _store.loadMetrics();
    final next = transform(
      current,
    ).copyWith(schemaVersion: UxMetricsSnapshot.currentSchemaVersion);
    await _store.saveMetrics(next);
    return next;
  }

  Future<UxMetricsSnapshot> recordTaskSuccess() =>
      _increment((s) => s.copyWith(taskSuccessCount: s.taskSuccessCount + 1));

  Future<UxMetricsSnapshot> recordTaskFailure() =>
      _increment((s) => s.copyWith(taskFailureCount: s.taskFailureCount + 1));

  Future<UxMetricsSnapshot> recordUndo() =>
      _increment((s) => s.copyWith(undoCount: s.undoCount + 1));

  Future<UxMetricsSnapshot> recordFormAbandon() =>
      _increment((s) => s.copyWith(formAbandonCount: s.formAbandonCount + 1));

  Future<UxMetricsSnapshot> recordValidationError() => _increment(
    (s) => s.copyWith(validationErrorCount: s.validationErrorCount + 1),
  );

  Future<UxMetricsSnapshot> recordSearch({bool zeroResults = false}) =>
      _increment(
        (s) => s.copyWith(
          searchCount: s.searchCount + 1,
          zeroResultSearchCount:
              s.zeroResultSearchCount + (zeroResults ? 1 : 0),
        ),
      );

  Future<UxMetricsSnapshot> recordRecommendationAccepted() => _increment(
    (s) => s.copyWith(
      recommendationAcceptedCount: s.recommendationAcceptedCount + 1,
    ),
  );

  Future<UxMetricsSnapshot> recordRecommendationDismissed() => _increment(
    (s) => s.copyWith(
      recommendationDismissedCount: s.recommendationDismissedCount + 1,
    ),
  );

  Future<void> resetAll() async {
    await _store.saveMetrics(UxMetricsSnapshot.empty);
  }
}
