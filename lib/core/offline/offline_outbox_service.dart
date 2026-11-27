import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../services/native_secure_vault_bridge.dart';

/// Explicit 6-state Offline-First Sync Status Contract (Section 36).
enum OfflineSyncStage {
  local('local', 'Lưu cục bộ'),
  pendingSync('pending_sync', 'Chờ đồng bộ'),
  syncing('syncing', 'Đang đồng bộ'),
  synced('synced', 'Đã đồng bộ'),
  conflict('conflict', 'Xung đột dữ liệu'),
  failed('failed', 'Đồng bộ lỗi');

  final String wireValue;
  final String labelVi;
  const OfflineSyncStage(this.wireValue, this.labelVi);

  static OfflineSyncStage fromWire(String? raw) {
    for (final s in values) {
      if (s.wireValue == raw) return s;
    }
    return OfflineSyncStage.local;
  }
}

enum OutboxMutationKind {
  upsert('upsert'),
  tombstoneDelete('tombstone_delete');

  final String wireValue;
  const OutboxMutationKind(this.wireValue);

  static OutboxMutationKind fromWire(String? raw) =>
      raw == 'tombstone_delete' ? tombstoneDelete : upsert;
}

class OutboxRecord extends Equatable {
  final String operationId;
  final String ownerId;
  final String entityType; // 'transaction' | 'task' | 'note' | 'calendar_event'
  final String entityId;
  final OutboxMutationKind mutationKind;
  final Map<String, dynamic> payload;
  final OfflineSyncStage stage;
  final int attemptCount;
  final int baseUpdatedAtEpochMs;
  final int nextRetryAtEpochMs;
  final int? inFlightAtMs;
  final bool isDeadLetter;
  final String? lastError;

  const OutboxRecord({
    required this.operationId,
    required this.ownerId,
    required this.entityType,
    required this.entityId,
    this.mutationKind = OutboxMutationKind.upsert,
    required this.payload,
    this.stage = OfflineSyncStage.pendingSync,
    this.attemptCount = 0,
    required this.baseUpdatedAtEpochMs,
    this.nextRetryAtEpochMs = 0,
    this.inFlightAtMs,
    this.isDeadLetter = false,
    this.lastError,
  });

  OutboxRecord copyWith({
    String? operationId,
    OfflineSyncStage? stage,
    int? attemptCount,
    int? nextRetryAtEpochMs,
    int? inFlightAtMs,
    bool clearInFlightAtMs = false,
    bool? isDeadLetter,
    String? lastError,
    bool clearError = false,
  }) {
    return OutboxRecord(
      operationId: operationId ?? this.operationId,
      ownerId: ownerId,
      entityType: entityType,
      entityId: entityId,
      mutationKind: mutationKind,
      payload: payload,
      stage: stage ?? this.stage,
      attemptCount: attemptCount ?? this.attemptCount,
      baseUpdatedAtEpochMs: baseUpdatedAtEpochMs,
      nextRetryAtEpochMs: nextRetryAtEpochMs ?? this.nextRetryAtEpochMs,
      inFlightAtMs: clearInFlightAtMs
          ? null
          : (inFlightAtMs ?? this.inFlightAtMs),
      isDeadLetter: isDeadLetter ?? this.isDeadLetter,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'operationId': operationId,
    'ownerId': ownerId,
    'entityType': entityType,
    'entityId': entityId,
    'mutationKind': mutationKind.wireValue,
    'payload': payload,
    'stage': stage.wireValue,
    'attemptCount': attemptCount,
    'baseUpdatedAtEpochMs': baseUpdatedAtEpochMs,
    'nextRetryAtEpochMs': nextRetryAtEpochMs,
    if (inFlightAtMs != null) 'inFlightAtMs': inFlightAtMs,
    'isDeadLetter': isDeadLetter,
    if (lastError != null) 'lastError': lastError,
  };

  factory OutboxRecord.fromJson(Map<String, dynamic> map) {
    return OutboxRecord(
      operationId: (map['operationId'] ?? '').toString(),
      ownerId: (map['ownerId'] ?? '').toString(),
      entityType: (map['entityType'] ?? '').toString(),
      entityId: (map['entityId'] ?? '').toString(),
      mutationKind: OutboxMutationKind.fromWire(
        map['mutationKind']?.toString(),
      ),
      payload: map['payload'] is Map
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : const <String, dynamic>{},
      stage: OfflineSyncStage.fromWire(map['stage']?.toString()),
      attemptCount: (map['attemptCount'] as num?)?.toInt() ?? 0,
      baseUpdatedAtEpochMs: (map['baseUpdatedAtEpochMs'] as num?)?.toInt() ?? 0,
      nextRetryAtEpochMs: (map['nextRetryAtEpochMs'] as num?)?.toInt() ?? 0,
      inFlightAtMs: (map['inFlightAtMs'] as num?)?.toInt(),
      isDeadLetter: map['isDeadLetter'] == true,
      lastError: map['lastError']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
    operationId,
    ownerId,
    entityType,
    entityId,
    mutationKind,
    payload,
    stage,
    attemptCount,
    baseUpdatedAtEpochMs,
    nextRetryAtEpochMs,
    inFlightAtMs,
    isDeadLetter,
    lastError,
  ];
}

class OfflineSyncTelemetry extends Equatable {
  final OfflineSyncStage overallStage;
  final int pendingCount;
  final int conflictCount;
  final int failedCount;
  final int deadLetterCount;
  final DateTime? lastSuccessfulSyncAt;

  const OfflineSyncTelemetry({
    required this.overallStage,
    required this.pendingCount,
    required this.conflictCount,
    required this.failedCount,
    this.deadLetterCount = 0,
    this.lastSuccessfulSyncAt,
  });

  static const OfflineSyncTelemetry idleSynced = OfflineSyncTelemetry(
    overallStage: OfflineSyncStage.synced,
    pendingCount: 0,
    conflictCount: 0,
    failedCount: 0,
    deadLetterCount: 0,
  );

  @override
  List<Object?> get props => [
    overallStage,
    pendingCount,
    conflictCount,
    failedCount,
    deadLetterCount,
    lastSuccessfulSyncAt,
  ];
}

enum OutboxRemoteOutcome {
  synced,
  conflict,
  transientFailure,
  permanentFailure,
}

/// Persistent, Idempotent Offline Outbox & Sync Recovery Coordinator (Section 36).
///
/// Guarantees:
/// - FIFO async operation serialization (`_opChain`) across ALL read/write/enqueue/
///   flush/remove/clear mutations so concurrent calls never clobber each other.
/// - Lease-based in-flight isolation (`inFlightAtMs`) so concurrent flushes never
///   double-execute an item, while stale crashed leases expire automatically.
/// - Dead-letter isolation (`isDeadLetter`) after `maxAttempts` or permanent failures.
/// - Corruption quarantine (`${storageKey}__corrupted_${nowMs}`) instead of silently
///   wiping corrupted persisted JSON queues.
/// - Strict UID-scoped storage & session isolation (`setActiveUserId` / `clearSessionOnSignOut`).
class OfflineOutboxService {
  static const String _keyPrefix = 'offline_outbox_queue_v1__u_';
  static const String _keyLastSyncPrefix = 'offline_outbox_last_sync__u_';
  static const int maxAttempts = 6;
  static const int baseBackoffMs = 1500;
  static const int maxBackoffMs = 300000;
  static const int defaultLeaseDurationMs = 60000;
  static const Uuid _uuid = Uuid();

  final NativeSecureVaultBridge _vault;
  final int leaseDurationMs;
  final StreamController<OfflineSyncTelemetry> _telemetryCtrl =
      StreamController<OfflineSyncTelemetry>.broadcast();
  final Map<String, List<OutboxRecord>> _cacheByUser =
      <String, List<OutboxRecord>>{};
  final Map<String, DateTime?> _lastSyncByUser = <String, DateTime?>{};

  Future<void> _opChain = Future<void>.value();
  String? _activeUserId;
  int _quarantinedCorruptionCount = 0;
  String? _lastCorruptionError;
  final List<String> _quarantinedKeys = <String>[];

  OfflineOutboxService({
    NativeSecureVaultBridge? vault,
    this.leaseDurationMs = defaultLeaseDurationMs,
  }) : _vault = vault ?? NativeSecureVaultBridge.instance;

  Stream<OfflineSyncTelemetry> watchTelemetry() => _telemetryCtrl.stream;

  String? get activeUserId => _activeUserId;
  int get quarantinedCorruptionCount => _quarantinedCorruptionCount;
  String? get lastCorruptionError => _lastCorruptionError;
  List<String> get quarantinedKeys =>
      List<String>.unmodifiable(_quarantinedKeys);

  static String storageKeyForUser(String userId) =>
      '$_keyPrefix${userId.trim()}';

  static int computeBackoffDelayMs(int attemptCount) {
    final shift = attemptCount.clamp(0, 10);
    return math.min(maxBackoffMs, baseBackoffMs * (1 << shift));
  }

  Future<T> _runSerialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _opChain = _opChain.then((_) async {
      try {
        final result = await action();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      }
    });
    return completer.future;
  }

  /// Binds the active signed-in UID and clears previous in-memory session state
  /// so account switches never leak or mix pending outbox commands across users.
  Future<void> setActiveUserId(String? userId) {
    return _runSerialized(() async {
      final clean = userId?.trim();
      final nextUid = (clean == null || clean.isEmpty) ? null : clean;
      if (_activeUserId != nextUid) {
        _cacheByUser.clear();
        _lastSyncByUser.clear();
      }
      _activeUserId = nextUid;
      if (nextUid != null) {
        final queue = await _loadQueueLocked(nextUid);
        _emit(_buildTelemetry(nextUid, queue));
      } else {
        _emit(OfflineSyncTelemetry.idleSynced);
      }
    });
  }

  /// Clears in-memory outbox session caches on sign-out without deleting
  /// persisted user-scoped vault records (so re-login preserves offline mutations).
  Future<void> clearSessionOnSignOut() {
    return _runSerialized(() async {
      _activeUserId = null;
      _cacheByUser.clear();
      _lastSyncByUser.clear();
      _emit(OfflineSyncTelemetry.idleSynced);
    });
  }

  void _assertAllowedUserScope(String userId) {
    final cleanUid = userId.trim();
    if (cleanUid.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'userId must not be empty');
    }
    if (_activeUserId != null && _activeUserId != cleanUid) {
      throw StateError(
        'Từ chối thao tác hàng đợi ngoại tuyến cho "$cleanUid" khi đang đăng nhập "$_activeUserId".',
      );
    }
  }

  Future<List<OutboxRecord>> loadQueue(String userId) {
    return _runSerialized(() async {
      final cleanUid = userId.trim();
      if (cleanUid.isEmpty) return const <OutboxRecord>[];
      _assertAllowedUserScope(cleanUid);
      return _loadQueueLocked(cleanUid);
    });
  }

  Future<List<OutboxRecord>> _loadQueueLocked(String userId) async {
    if (_cacheByUser.containsKey(userId)) {
      return List<OutboxRecord>.unmodifiable(_cacheByUser[userId]!);
    }
    final storageKey = storageKeyForUser(userId);
    final raw = await _vault.readSecret(storageKey);
    final syncRaw = await _vault.readSecret('$_keyLastSyncPrefix$userId');
    if (syncRaw != null) {
      final ms = int.tryParse(syncRaw);
      if (ms != null && ms > 0) {
        _lastSyncByUser[userId] = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    if (raw == null || raw.trim().isEmpty) {
      _cacheByUser[userId] = <OutboxRecord>[];
      return const <OutboxRecord>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('Outbox payload root is not a JSON List.');
      }
      final list = <OutboxRecord>[];
      for (final entry in decoded) {
        if (entry is! Map) {
          throw const FormatException('Outbox item is not a JSON object.');
        }
        final rec = OutboxRecord.fromJson(Map<String, dynamic>.from(entry));
        if (rec.operationId.trim().isEmpty ||
            rec.ownerId.trim().isEmpty ||
            rec.entityType.trim().isEmpty ||
            rec.entityId.trim().isEmpty) {
          throw const FormatException(
            'Outbox item is missing required fields.',
          );
        }
        list.add(rec);
      }
      _cacheByUser[userId] = list;
      return List<OutboxRecord>.unmodifiable(list);
    } catch (e) {
      await _quarantineCorruptedPayload(
        userId: userId,
        storageKey: storageKey,
        rawPayload: raw,
        error: e,
      );
      _cacheByUser[userId] = <OutboxRecord>[];
      return const <OutboxRecord>[];
    }
  }

  Future<void> _quarantineCorruptedPayload({
    required String userId,
    required String storageKey,
    required String rawPayload,
    required Object error,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var quarantineKey = '${storageKey}__corrupted_$nowMs';
    if (await _vault.readSecret(quarantineKey) != null) {
      quarantineKey =
          '${storageKey}__corrupted_${nowMs}_${_quarantinedCorruptionCount + 1}';
    }
    await _vault.writeSecret(key: quarantineKey, value: rawPayload);
    await _vault.deleteSecret(storageKey);
    _quarantinedCorruptionCount += 1;
    _quarantinedKeys.add(quarantineKey);
    _lastCorruptionError =
        'Dữ liệu hàng đợi ngoại tuyến bị hỏng ($userId) đã được cách ly tại $quarantineKey: $error';
  }

  /// Idempotently enqueues a mutation or tombstone when offline or when a remote write times out.
  Future<OutboxRecord> enqueue(OutboxRecord record) {
    return _runSerialized(() async {
      final ownerId = record.ownerId.trim();
      _assertAllowedUserScope(ownerId);

      final stableOpId = record.operationId.trim().isNotEmpty
          ? record.operationId.trim()
          : _uuid.v4();
      final normalized = OutboxRecord(
        operationId: stableOpId,
        ownerId: ownerId,
        entityType: record.entityType,
        entityId: record.entityId,
        mutationKind: record.mutationKind,
        payload: record.payload,
        stage: record.stage,
        attemptCount: record.attemptCount,
        baseUpdatedAtEpochMs: record.baseUpdatedAtEpochMs,
        nextRetryAtEpochMs: record.nextRetryAtEpochMs,
        inFlightAtMs: record.inFlightAtMs,
        isDeadLetter: record.isDeadLetter,
        lastError: record.lastError,
      );

      final queue = List<OutboxRecord>.from(await _loadQueueLocked(ownerId));
      final existingIdx = queue.indexWhere(
        (r) => r.operationId == normalized.operationId,
      );
      if (existingIdx >= 0) {
        return queue[existingIdx];
      }

      // Coalesce superseded uncommitted non-leased upserts on the same entity when deleting
      if (normalized.mutationKind == OutboxMutationKind.tombstoneDelete) {
        queue.removeWhere(
          (r) =>
              r.entityType == normalized.entityType &&
              r.entityId == normalized.entityId &&
              r.stage == OfflineSyncStage.pendingSync &&
              r.inFlightAtMs == null,
        );
      }

      queue.add(normalized);
      await _persistQueueLocked(ownerId, queue);
      return normalized;
    });
  }

  /// Flushes due outbox items using [executor], applying atomic in-flight leases,
  /// exponential backoff, conflict isolation, and dead-letter quarantine.
  Future<OfflineSyncTelemetry> flushDue({
    required String userId,
    required Future<OutboxRemoteOutcome> Function(OutboxRecord record) executor,
    DateTime? nowOverride,
  }) async {
    final cleanUid = userId.trim();
    final now = nowOverride ?? DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    // Phase 1: Under _opChain, acquire atomic in-flight leases on due records.
    final leasedItems = await _runSerialized<List<OutboxRecord>>(() async {
      _assertAllowedUserScope(cleanUid);
      final queue = List<OutboxRecord>.from(await _loadQueueLocked(cleanUid));
      if (queue.isEmpty) {
        final snap = _buildTelemetry(cleanUid, queue);
        _emit(snap);
        return const <OutboxRecord>[];
      }

      final toLease = <OutboxRecord>[];
      var mutated = false;
      for (var i = 0; i < queue.length; i++) {
        final item = queue[i];
        if (item.isDeadLetter ||
            item.stage == OfflineSyncStage.conflict ||
            item.stage == OfflineSyncStage.failed) {
          continue;
        }
        if (item.nextRetryAtEpochMs > nowMs) {
          continue;
        }
        final activeLease =
            item.inFlightAtMs != null &&
            (nowMs - item.inFlightAtMs!) < leaseDurationMs;
        if (activeLease) {
          continue;
        }
        final leased = item.copyWith(
          stage: OfflineSyncStage.syncing,
          inFlightAtMs: nowMs,
        );
        queue[i] = leased;
        toLease.add(leased);
        mutated = true;
      }

      if (mutated) {
        await _persistQueueLocked(cleanUid, queue);
        _emit(
          OfflineSyncTelemetry(
            overallStage: OfflineSyncStage.syncing,
            pendingCount: queue
                .where(
                  (r) =>
                      !r.isDeadLetter &&
                      (r.stage == OfflineSyncStage.pendingSync ||
                          r.stage == OfflineSyncStage.syncing),
                )
                .length,
            conflictCount: queue
                .where((r) => r.stage == OfflineSyncStage.conflict)
                .length,
            failedCount: queue
                .where(
                  (r) => r.isDeadLetter || r.stage == OfflineSyncStage.failed,
                )
                .length,
            deadLetterCount: queue.where((r) => r.isDeadLetter).length,
            lastSuccessfulSyncAt: _lastSyncByUser[cleanUid],
          ),
        );
      } else {
        _emit(_buildTelemetry(cleanUid, queue));
      }
      return toLease;
    });

    if (leasedItems.isEmpty) {
      return _runSerialized(() async {
        final q = await _loadQueueLocked(cleanUid);
        return _buildTelemetry(cleanUid, q);
      });
    }

    // Phase 2: Execute remote mutations outside _opChain so concurrent enqueues
    // are never blocked or dropped while network calls are in flight.
    final results =
        <String, ({OutboxRemoteOutcome outcome, String? errText})>{};
    for (final item in leasedItems) {
      OutboxRemoteOutcome outcome;
      String? errText;
      try {
        outcome = await executor(item);
      } catch (e) {
        outcome = OutboxRemoteOutcome.transientFailure;
        errText = e.toString();
      }
      results[item.operationId] = (outcome: outcome, errText: errText);
    }

    // Phase 3: Under _opChain, reconcile outcomes into the latest queue by operationId.
    return _runSerialized(() async {
      final latestQueue = List<OutboxRecord>.from(
        await _loadQueueLocked(cleanUid),
      );
      var anySynced = false;

      for (final entry in results.entries) {
        final opId = entry.key;
        final idx = latestQueue.indexWhere((r) => r.operationId == opId);
        if (idx < 0) continue;

        final item = latestQueue[idx];
        // Ensure we still own the active lease token for this item.
        if (item.inFlightAtMs != nowMs) continue;

        switch (entry.value.outcome) {
          case OutboxRemoteOutcome.synced:
            latestQueue.removeAt(idx);
            anySynced = true;
          case OutboxRemoteOutcome.conflict:
            latestQueue[idx] = item.copyWith(
              stage: OfflineSyncStage.conflict,
              clearInFlightAtMs: true,
              lastError: 'Phát hiện phiên bản mới hơn từ thiết bị khác.',
            );
          case OutboxRemoteOutcome.permanentFailure:
            latestQueue[idx] = item.copyWith(
              stage: OfflineSyncStage.failed,
              isDeadLetter: true,
              clearInFlightAtMs: true,
              lastError:
                  entry.value.errText ?? 'Dữ liệu không hợp lệ với máy chủ.',
            );
          case OutboxRemoteOutcome.transientFailure:
            final nextAttempt = item.attemptCount + 1;
            if (nextAttempt >= maxAttempts) {
              latestQueue[idx] = item.copyWith(
                stage: OfflineSyncStage.failed,
                isDeadLetter: true,
                attemptCount: nextAttempt,
                clearInFlightAtMs: true,
                lastError:
                    entry.value.errText ??
                    'Vượt quá số lần thử đồng bộ tự động (chuyển vào Dead-Letter).',
              );
            } else {
              final delay = computeBackoffDelayMs(item.attemptCount);
              latestQueue[idx] = item.copyWith(
                stage: OfflineSyncStage.pendingSync,
                isDeadLetter: false,
                attemptCount: nextAttempt,
                nextRetryAtEpochMs: nowMs + delay,
                clearInFlightAtMs: true,
                lastError: entry.value.errText,
              );
            }
        }
      }

      if (anySynced) {
        _lastSyncByUser[cleanUid] = now;
        await _vault.writeSecret(
          key: '$_keyLastSyncPrefix$cleanUid',
          value: nowMs.toString(),
        );
      }

      await _persistQueueLocked(cleanUid, latestQueue);
      return _buildTelemetry(cleanUid, latestQueue);
    });
  }

  /// Resolves a conflicted record either by keeping local (`keepLocalAndRetry = true`) or discarding local.
  Future<OfflineSyncTelemetry> resolveConflict({
    required String userId,
    required String operationId,
    required bool keepLocalAndRetry,
  }) {
    return _runSerialized(() async {
      final cleanUid = userId.trim();
      _assertAllowedUserScope(cleanUid);
      final queue = List<OutboxRecord>.from(await _loadQueueLocked(cleanUid));
      final idx = queue.indexWhere((r) => r.operationId == operationId);
      if (idx >= 0) {
        if (keepLocalAndRetry) {
          queue[idx] = queue[idx].copyWith(
            stage: OfflineSyncStage.pendingSync,
            attemptCount: 0,
            nextRetryAtEpochMs: 0,
            clearInFlightAtMs: true,
            isDeadLetter: false,
            clearError: true,
          );
        } else {
          queue.removeAt(idx);
        }
        await _persistQueueLocked(cleanUid, queue);
      }
      return _buildTelemetry(cleanUid, queue);
    });
  }

  /// Removes a single entry by [operationId] under serialized queue lock.
  Future<bool> remove({required String userId, required String operationId}) {
    return _runSerialized(() async {
      final cleanUid = userId.trim();
      _assertAllowedUserScope(cleanUid);
      final queue = List<OutboxRecord>.from(await _loadQueueLocked(cleanUid));
      final before = queue.length;
      queue.removeWhere((r) => r.operationId == operationId);
      if (queue.length != before) {
        await _persistQueueLocked(cleanUid, queue);
        return true;
      }
      return false;
    });
  }

  /// Clears all active outbox items for [userId] under serialized lock.
  Future<void> clear(String userId) {
    return _runSerialized(() async {
      final cleanUid = userId.trim();
      _assertAllowedUserScope(cleanUid);
      _cacheByUser[cleanUid] = <OutboxRecord>[];
      _lastSyncByUser.remove(cleanUid);
      await _vault.deleteSecret(storageKeyForUser(cleanUid));
      await _vault.deleteSecret('$_keyLastSyncPrefix$cleanUid');
      _emit(_buildTelemetry(cleanUid, const <OutboxRecord>[]));
    });
  }

  Future<List<OutboxRecord>> getDeadLetters(String userId) {
    return _runSerialized(() async {
      final cleanUid = userId.trim();
      _assertAllowedUserScope(cleanUid);
      final queue = await _loadQueueLocked(cleanUid);
      return List<OutboxRecord>.unmodifiable(
        queue.where(
          (r) => r.isDeadLetter || r.stage == OfflineSyncStage.failed,
        ),
      );
    });
  }

  Future<OfflineSyncTelemetry> retryDeadLetter({
    required String userId,
    required String operationId,
  }) {
    return _runSerialized(() async {
      final cleanUid = userId.trim();
      _assertAllowedUserScope(cleanUid);
      final queue = List<OutboxRecord>.from(await _loadQueueLocked(cleanUid));
      final idx = queue.indexWhere((r) => r.operationId == operationId);
      if (idx >= 0) {
        queue[idx] = queue[idx].copyWith(
          stage: OfflineSyncStage.pendingSync,
          isDeadLetter: false,
          attemptCount: 0,
          nextRetryAtEpochMs: 0,
          clearInFlightAtMs: true,
          clearError: true,
        );
        await _persistQueueLocked(cleanUid, queue);
      }
      return _buildTelemetry(cleanUid, queue);
    });
  }

  OfflineSyncTelemetry currentTelemetry(String userId) {
    final queue = _cacheByUser[userId] ?? const <OutboxRecord>[];
    return _buildTelemetry(userId, queue);
  }

  Future<void> _persistQueueLocked(
    String userId,
    List<OutboxRecord> queue,
  ) async {
    _cacheByUser[userId] = queue;
    final storageKey = storageKeyForUser(userId);
    if (queue.isEmpty) {
      await _vault.deleteSecret(storageKey);
    } else {
      await _vault.writeSecret(
        key: storageKey,
        value: jsonEncode(queue.map((e) => e.toJson()).toList()),
      );
    }
    _emit(_buildTelemetry(userId, queue));
  }

  OfflineSyncTelemetry _buildTelemetry(
    String userId,
    List<OutboxRecord> queue,
  ) {
    final conflicts = queue
        .where((r) => r.stage == OfflineSyncStage.conflict)
        .length;
    final failed = queue
        .where((r) => r.isDeadLetter || r.stage == OfflineSyncStage.failed)
        .length;
    final deadLetters = queue.where((r) => r.isDeadLetter).length;
    final pending = queue
        .where(
          (r) =>
              !r.isDeadLetter &&
              (r.stage == OfflineSyncStage.pendingSync ||
                  r.stage == OfflineSyncStage.syncing),
        )
        .length;

    final overall = conflicts > 0
        ? OfflineSyncStage.conflict
        : failed > 0
        ? OfflineSyncStage.failed
        : pending > 0
        ? OfflineSyncStage.pendingSync
        : OfflineSyncStage.synced;

    return OfflineSyncTelemetry(
      overallStage: overall,
      pendingCount: pending,
      conflictCount: conflicts,
      failedCount: failed,
      deadLetterCount: deadLetters,
      lastSuccessfulSyncAt: _lastSyncByUser[userId],
    );
  }

  void _emit(OfflineSyncTelemetry snap) {
    if (!_telemetryCtrl.isClosed) {
      _telemetryCtrl.add(snap);
    }
  }

  Future<void> dispose() async {
    try {
      await _opChain;
    } catch (_) {}
    await _telemetryCtrl.close();
  }
}
