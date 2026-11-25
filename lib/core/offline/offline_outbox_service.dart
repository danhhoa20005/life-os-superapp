import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';

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
    this.lastError,
  });

  OutboxRecord copyWith({
    OfflineSyncStage? stage,
    int? attemptCount,
    int? nextRetryAtEpochMs,
    String? lastError,
    bool clearError = false,
  }) {
    return OutboxRecord(
      operationId: operationId,
      ownerId: ownerId,
      entityType: entityType,
      entityId: entityId,
      mutationKind: mutationKind,
      payload: payload,
      stage: stage ?? this.stage,
      attemptCount: attemptCount ?? this.attemptCount,
      baseUpdatedAtEpochMs: baseUpdatedAtEpochMs,
      nextRetryAtEpochMs: nextRetryAtEpochMs ?? this.nextRetryAtEpochMs,
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
    lastError,
  ];
}

class OfflineSyncTelemetry extends Equatable {
  final OfflineSyncStage overallStage;
  final int pendingCount;
  final int conflictCount;
  final int failedCount;
  final DateTime? lastSuccessfulSyncAt;

  const OfflineSyncTelemetry({
    required this.overallStage,
    required this.pendingCount,
    required this.conflictCount,
    required this.failedCount,
    this.lastSuccessfulSyncAt,
  });

  static const OfflineSyncTelemetry idleSynced = OfflineSyncTelemetry(
    overallStage: OfflineSyncStage.synced,
    pendingCount: 0,
    conflictCount: 0,
    failedCount: 0,
  );

  @override
  List<Object?> get props => [
    overallStage,
    pendingCount,
    conflictCount,
    failedCount,
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
/// Supports:
/// - Scoped per-user storage in `NativeSecureVaultBridge` (encrypted Android Keystore on device).
/// - `operationId` idempotency so retries never duplicate mutations.
/// - Exponential backoff (`baseBackoffMs * 2^attempt`, capped at 5 minutes).
/// - Tombstone deletes & deterministic version/timestamp conflict detection.
class OfflineOutboxService {
  static const String _keyPrefix = 'offline_outbox_queue_v1__u_';
  static const String _keyLastSyncPrefix = 'offline_outbox_last_sync__u_';
  static const int maxAttempts = 6;
  static const int baseBackoffMs = 1500;
  static const int maxBackoffMs = 300000;

  final NativeSecureVaultBridge _vault;
  final StreamController<OfflineSyncTelemetry> _telemetryCtrl =
      StreamController<OfflineSyncTelemetry>.broadcast();
  final Map<String, List<OutboxRecord>> _cacheByUser =
      <String, List<OutboxRecord>>{};
  final Map<String, DateTime?> _lastSyncByUser = <String, DateTime?>{};

  OfflineOutboxService({NativeSecureVaultBridge? vault})
    : _vault = vault ?? NativeSecureVaultBridge.instance;

  Stream<OfflineSyncTelemetry> watchTelemetry() => _telemetryCtrl.stream;

  static int computeBackoffDelayMs(int attemptCount) {
    final shift = attemptCount.clamp(0, 10);
    return math.min(maxBackoffMs, baseBackoffMs * (1 << shift));
  }

  Future<List<OutboxRecord>> loadQueue(String userId) async {
    if (_cacheByUser.containsKey(userId)) {
      return List<OutboxRecord>.unmodifiable(_cacheByUser[userId]!);
    }
    final raw = await _vault.readSecret('$_keyPrefix$userId');
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
      if (decoded is List) {
        final list = decoded
            .whereType<Map<dynamic, dynamic>>()
            .map((e) => OutboxRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _cacheByUser[userId] = list;
        return List<OutboxRecord>.unmodifiable(list);
      }
    } catch (_) {}
    _cacheByUser[userId] = <OutboxRecord>[];
    return const <OutboxRecord>[];
  }

  /// Idempotently enqueues a mutation or tombstone when offline or when a remote write times out.
  Future<OutboxRecord> enqueue(OutboxRecord record) async {
    final queue = List<OutboxRecord>.from(await loadQueue(record.ownerId));
    final existingIdx = queue.indexWhere(
      (r) => r.operationId == record.operationId,
    );
    if (existingIdx >= 0) {
      return queue[existingIdx];
    }
    // Coalesce superseded uncommitted upserts/tombstones on the same entity when appropriate
    if (record.mutationKind == OutboxMutationKind.tombstoneDelete) {
      queue.removeWhere(
        (r) =>
            r.entityType == record.entityType &&
            r.entityId == record.entityId &&
            r.stage == OfflineSyncStage.pendingSync,
      );
    }
    queue.add(record);
    await _persistQueue(record.ownerId, queue);
    return record;
  }

  /// Flushes due outbox items using [executor], applying exponential backoff and conflict isolation.
  Future<OfflineSyncTelemetry> flushDue({
    required String userId,
    required Future<OutboxRemoteOutcome> Function(OutboxRecord record) executor,
    DateTime? nowOverride,
  }) async {
    final now = nowOverride ?? DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final queue = List<OutboxRecord>.from(await loadQueue(userId));
    if (queue.isEmpty) {
      final snap = _buildTelemetry(userId, queue);
      _emit(snap);
      return snap;
    }

    _emit(
      OfflineSyncTelemetry(
        overallStage: OfflineSyncStage.syncing,
        pendingCount: queue.length,
        conflictCount: queue
            .where((r) => r.stage == OfflineSyncStage.conflict)
            .length,
        failedCount: queue
            .where((r) => r.stage == OfflineSyncStage.failed)
            .length,
        lastSuccessfulSyncAt: _lastSyncByUser[userId],
      ),
    );

    final remaining = <OutboxRecord>[];
    var anySynced = false;

    for (final item in queue) {
      if (item.stage == OfflineSyncStage.conflict ||
          item.stage == OfflineSyncStage.failed) {
        remaining.add(item);
        continue;
      }
      if (item.nextRetryAtEpochMs > nowMs) {
        remaining.add(item);
        continue;
      }

      OutboxRemoteOutcome outcome;
      String? errText;
      try {
        outcome = await executor(item);
      } catch (e) {
        outcome = OutboxRemoteOutcome.transientFailure;
        errText = e.toString();
      }

      switch (outcome) {
        case OutboxRemoteOutcome.synced:
          anySynced = true;
        case OutboxRemoteOutcome.conflict:
          remaining.add(
            item.copyWith(
              stage: OfflineSyncStage.conflict,
              lastError: 'Phát hiện phiên bản mới hơn từ thiết bị khác.',
            ),
          );
        case OutboxRemoteOutcome.permanentFailure:
          remaining.add(
            item.copyWith(
              stage: OfflineSyncStage.failed,
              lastError: errText ?? 'Dữ liệu không hợp lệ với máy chủ.',
            ),
          );
        case OutboxRemoteOutcome.transientFailure:
          final nextAttempt = item.attemptCount + 1;
          if (nextAttempt >= maxAttempts) {
            remaining.add(
              item.copyWith(
                stage: OfflineSyncStage.failed,
                attemptCount: nextAttempt,
                lastError: errText ?? 'Vượt quá số lần thử đồng bộ tự động.',
              ),
            );
          } else {
            final delay = computeBackoffDelayMs(item.attemptCount);
            remaining.add(
              item.copyWith(
                stage: OfflineSyncStage.pendingSync,
                attemptCount: nextAttempt,
                nextRetryAtEpochMs: nowMs + delay,
                lastError: errText,
              ),
            );
          }
      }
    }

    if (anySynced) {
      _lastSyncByUser[userId] = now;
      await _vault.writeSecret(
        key: '$_keyLastSyncPrefix$userId',
        value: nowMs.toString(),
      );
    }

    await _persistQueue(userId, remaining);
    return _buildTelemetry(userId, remaining);
  }

  /// Resolves a conflicted record either by keeping local (`retryLocal = true`) or discarding local (`retryLocal = false`).
  Future<OfflineSyncTelemetry> resolveConflict({
    required String userId,
    required String operationId,
    required bool keepLocalAndRetry,
  }) async {
    final queue = List<OutboxRecord>.from(await loadQueue(userId));
    final idx = queue.indexWhere((r) => r.operationId == operationId);
    if (idx >= 0) {
      if (keepLocalAndRetry) {
        queue[idx] = queue[idx].copyWith(
          stage: OfflineSyncStage.pendingSync,
          attemptCount: 0,
          nextRetryAtEpochMs: 0,
          clearError: true,
        );
      } else {
        queue.removeAt(idx);
      }
      await _persistQueue(userId, queue);
    }
    return _buildTelemetry(userId, queue);
  }

  OfflineSyncTelemetry currentTelemetry(String userId) {
    final queue = _cacheByUser[userId] ?? const <OutboxRecord>[];
    return _buildTelemetry(userId, queue);
  }

  Future<void> _persistQueue(String userId, List<OutboxRecord> queue) async {
    _cacheByUser[userId] = queue;
    if (queue.isEmpty) {
      await _vault.deleteSecret('$_keyPrefix$userId');
    } else {
      await _vault.writeSecret(
        key: '$_keyPrefix$userId',
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
        .where((r) => r.stage == OfflineSyncStage.failed)
        .length;
    final pending = queue
        .where((r) => r.stage == OfflineSyncStage.pendingSync)
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
      lastSuccessfulSyncAt: _lastSyncByUser[userId],
    );
  }

  void _emit(OfflineSyncTelemetry snap) {
    if (!_telemetryCtrl.isClosed) {
      _telemetryCtrl.add(snap);
    }
  }

  Future<void> dispose() async {
    await _telemetryCtrl.close();
  }
}
