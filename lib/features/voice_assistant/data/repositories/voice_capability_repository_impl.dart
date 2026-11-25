import 'dart:convert';

import '../../../../core/services/native_secure_vault_bridge.dart';
import '../../domain/entities/voice_engine_capability.dart';
import '../../domain/repositories/voice_capability_repository.dart';
import '../../domain/services/engine_selection_policy.dart';
import '../../domain/services/monotonic_clock.dart';

/// Injectable key-value store abstraction for encrypted capability cache persistence.
abstract interface class VoiceCapabilityKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureVaultVoiceCapabilityStore implements VoiceCapabilityKeyValueStore {
  final NativeSecureVaultBridge _vault;

  SecureVaultVoiceCapabilityStore([NativeSecureVaultBridge? vault])
    : _vault = vault ?? NativeSecureVaultBridge.instance;

  @override
  Future<String?> read(String key) => _vault.readSecret(key);

  @override
  Future<void> write(String key, String value) =>
      _vault.writeSecret(key: key, value: value);

  @override
  Future<void> delete(String key) => _vault.deleteSecret(key);
}

class InMemoryVoiceCapabilityStore implements VoiceCapabilityKeyValueStore {
  final Map<String, String> _storage = <String, String>{};

  @override
  Future<String?> read(String key) async => _storage[key];

  @override
  Future<void> write(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _storage.remove(key);
  }
}

/// JSON-backed capability cache repository enforcing TTL & environment scoping (`VOICE-008`).
class VoiceCapabilityRepositoryImpl implements VoiceCapabilityRepository {
  static const String storageKey = 'voice_v2_engine_capabilities_v1';

  final VoiceCapabilityKeyValueStore _store;
  final MonotonicClock _clock;
  final int _defaultTtlMs;

  VoiceCapabilityRepositoryImpl({
    VoiceCapabilityKeyValueStore? store,
    MonotonicClock? clock,
    int defaultTtlMs = VoiceEngineCapabilityEntry.defaultTtlMs,
  }) : _store = store ?? SecureVaultVoiceCapabilityStore(),
       _clock = clock ?? SystemMonotonicClock(),
       _defaultTtlMs = defaultTtlMs;

  @override
  Future<List<VoiceEngineCapabilityEntry>> loadEntries() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <VoiceEngineCapabilityEntry>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <VoiceEngineCapabilityEntry>[];
      final entries = <VoiceEngineCapabilityEntry>[];
      for (final item in decoded) {
        if (item is Map) {
          final parsed = VoiceEngineCapabilityEntry.fromJson(
            Map<String, Object?>.from(item),
          );
          if (parsed != null) {
            entries.add(parsed);
          }
        }
      }
      return List<VoiceEngineCapabilityEntry>.unmodifiable(entries);
    } catch (_) {
      return const <VoiceEngineCapabilityEntry>[];
    }
  }

  @override
  Future<void> upsertEntry(VoiceEngineCapabilityEntry entry) async {
    final entries = List<VoiceEngineCapabilityEntry>.from(await loadEntries());
    final idx = entries.indexWhere(
      (e) =>
          e.engineId == entry.engineId &&
          e.matchesEnvironment(
            androidSdkInt: entry.androidSdkInt,
            osBuildFingerprint: entry.osBuildFingerprint,
            recognitionServiceVersion: entry.recognitionServiceVersion,
            locale: entry.locale,
            audioRoute: entry.audioRoute,
          ),
    );
    if (idx >= 0) {
      entries[idx] = entry;
    } else {
      entries.add(entry);
    }
    await _persist(entries);
  }

  @override
  Future<void> recordSuccess({
    required VoiceEngineId engineId,
    required VoiceEnvironmentSnapshot environment,
  }) async {
    final nowMs = _resolveEpochMs(environment);
    final entries = List<VoiceEngineCapabilityEntry>.from(await loadEntries());
    final idx = _findMatchingIndex(entries, engineId, environment);
    if (idx >= 0 && !entries[idx].isExpired(nowMs)) {
      entries[idx] = entries[idx].recordSuccess(nowEpochMs: nowMs);
    } else {
      final fresh = VoiceEngineCapabilityEntry(
        engineId: engineId,
        androidSdkInt: environment.androidSdkInt,
        osBuildFingerprint: environment.osBuildFingerprint,
        recognitionServiceVersion: environment.recognitionServiceVersion,
        locale: environment.locale,
        audioRoute: environment.audioRoute,
        isAvailable: true,
        supportsVietnamese: true,
        checkedAtEpochMs: nowMs,
        ttlMs: _defaultTtlMs,
        recentSuccessCount: 1,
      );
      if (idx >= 0) {
        entries[idx] = fresh;
      } else {
        entries.add(fresh);
      }
    }
    await _persist(entries);
  }

  @override
  Future<void> recordError({
    required VoiceEngineId engineId,
    required VoiceEnvironmentSnapshot environment,
    required String? errorCode,
    bool? stillAvailable,
    bool? stillSupportsVietnamese,
  }) async {
    final nowMs = _resolveEpochMs(environment);
    final entries = List<VoiceEngineCapabilityEntry>.from(await loadEntries());
    final idx = _findMatchingIndex(entries, engineId, environment);
    if (idx >= 0 && !entries[idx].isExpired(nowMs)) {
      entries[idx] = entries[idx].recordError(
        nowEpochMs: nowMs,
        errorCode: errorCode,
        stillAvailable: stillAvailable,
        stillSupportsVietnamese: stillSupportsVietnamese,
      );
    } else {
      final fresh = VoiceEngineCapabilityEntry(
        engineId: engineId,
        androidSdkInt: environment.androidSdkInt,
        osBuildFingerprint: environment.osBuildFingerprint,
        recognitionServiceVersion: environment.recognitionServiceVersion,
        locale: environment.locale,
        audioRoute: environment.audioRoute,
        isAvailable: stillAvailable ?? true,
        supportsVietnamese: stillSupportsVietnamese ?? true,
        checkedAtEpochMs: nowMs,
        ttlMs: _defaultTtlMs,
        recentErrorCount: 1,
        consecutiveErrorCount: 1,
        lastErrorCode: errorCode,
      );
      if (idx >= 0) {
        entries[idx] = fresh;
      } else {
        entries.add(fresh);
      }
    }
    await _persist(entries);
  }

  @override
  Future<void> clearAll() => _store.delete(storageKey);

  int _resolveEpochMs(VoiceEnvironmentSnapshot env) {
    return env.nowEpochMs > 0
        ? env.nowEpochMs
        : _clock.wallNow.millisecondsSinceEpoch;
  }

  int _findMatchingIndex(
    List<VoiceEngineCapabilityEntry> entries,
    VoiceEngineId engineId,
    VoiceEnvironmentSnapshot environment,
  ) {
    return entries.indexWhere(
      (e) =>
          e.engineId == engineId &&
          e.matchesEnvironment(
            androidSdkInt: environment.androidSdkInt,
            osBuildFingerprint: environment.osBuildFingerprint,
            recognitionServiceVersion: environment.recognitionServiceVersion,
            locale: environment.locale,
            audioRoute: environment.audioRoute,
          ),
    );
  }

  Future<void> _persist(List<VoiceEngineCapabilityEntry> entries) {
    final encoded = jsonEncode(
      entries.map((e) => e.toJson()).toList(growable: false),
    );
    return _store.write(storageKey, encoded);
  }
}
