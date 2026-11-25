import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/native_secure_vault_bridge.dart';

/// Account-scoped encrypted local draft persistence backed by [NativeSecureVaultBridge].
///
/// Guarantees strict account isolation on shared devices:
/// - Storage keys are namespaced by `userId` (`ux_form_draft_v1__u_<uid>__<formId>`).
/// - `ownerUserId` is stamped inside every persisted JSON payload and verified
///   on load so Account B can never restore Account A's draft.
abstract final class LocalDraftStore {
  static const String _keyPrefix = 'ux_form_draft_v1';
  static const String _indexPrefix = 'ux_form_draft_index_v1';

  static const List<String> _knownFormIds = <String>[
    'quick_hub_omni',
    'quick_tx_form',
    'quick_tx_vehicle_form',
    'quick_transfer_form',
    'quick_split_form',
    'quick_task_form',
    'quick_reminder_form',
    'quick_grocery_note_form',
  ];

  static final Map<String, Map<String, dynamic>> _memoryCache =
      <String, Map<String, dynamic>>{};
  static final Map<String, Set<String>> _knownFormIdsByUser =
      <String, Set<String>>{};

  @visibleForTesting
  static NativeSecureVaultBridge? vaultOverride;

  static NativeSecureVaultBridge get _vault =>
      vaultOverride ?? NativeSecureVaultBridge.instance;

  static String _sanitizeSegment(String raw) =>
      raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');

  /// Canonical storage key for a `(userId, formId)` draft pair.
  static String storageKey({required String userId, required String formId}) {
    final safeUid = _sanitizeSegment(userId);
    final safeForm = _sanitizeSegment(formId);
    return '${_keyPrefix}__u_${safeUid}__$safeForm';
  }

  static String _indexKey(String userId) {
    final safeUid = _sanitizeSegment(userId);
    return '${_indexPrefix}__u_$safeUid';
  }

  /// Persists a JSON-serializable [payload] scoped strictly to [userId] + [formId].
  static Future<void> saveDraft({
    required String userId,
    required String formId,
    required Map<String, dynamic> payload,
  }) async {
    final cleanUid = userId.trim();
    final cleanForm = formId.trim();
    if (cleanUid.isEmpty || cleanForm.isEmpty) return;

    final key = storageKey(userId: cleanUid, formId: cleanForm);
    final envelope = <String, dynamic>{
      ...payload,
      'ownerUserId': cleanUid,
      'formId': cleanForm,
      'updatedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
    };

    _memoryCache[key] = _deepCloneMap(envelope);
    final tracked = _knownFormIdsByUser.putIfAbsent(cleanUid, () => <String>{});
    final addedNew = tracked.add(cleanForm);

    await _vault.writeSecret(key: key, value: jsonEncode(envelope));
    if (addedNew) {
      await _persistUserFormIndex(cleanUid, tracked);
    }
  }

  /// Restores the draft for `(userId, formId)` ONLY when the stored `ownerUserId`
  /// matches [userId] strictly. Returns `null` if absent, invalid, or owned by another user.
  static Future<Map<String, dynamic>?> loadDraft({
    required String userId,
    required String formId,
  }) async {
    final cleanUid = userId.trim();
    final cleanForm = formId.trim();
    if (cleanUid.isEmpty || cleanForm.isEmpty) return null;

    final key = storageKey(userId: cleanUid, formId: cleanForm);
    final cached = _memoryCache[key];
    if (cached != null) {
      final cachedOwner = (cached['ownerUserId'] as String?)?.trim();
      final cachedForm = (cached['formId'] as String?)?.trim();
      if (cachedOwner == cleanUid &&
          (cachedForm == null || cachedForm == cleanForm)) {
        return _deepCloneMap(cached);
      }
      _memoryCache.remove(key);
      return null;
    }

    final raw = await _vault.readSecret(key);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final storedOwner = (map['ownerUserId'] as String?)?.trim();
      final storedForm = (map['formId'] as String?)?.trim();
      if (storedOwner != cleanUid) {
        return null;
      }
      if (storedForm != null &&
          storedForm.isNotEmpty &&
          storedForm != cleanForm) {
        return null;
      }
      _memoryCache[key] = _deepCloneMap(map);
      _knownFormIdsByUser
          .putIfAbsent(cleanUid, () => <String>{})
          .add(cleanForm);
      return _deepCloneMap(map);
    } catch (_) {
      return null;
    }
  }

  /// Removes a single `(userId, formId)` draft from memory and encrypted vault storage.
  static Future<void> clearDraft({
    required String userId,
    required String formId,
  }) async {
    final cleanUid = userId.trim();
    final cleanForm = formId.trim();
    if (cleanUid.isEmpty || cleanForm.isEmpty) return;

    final key = storageKey(userId: cleanUid, formId: cleanForm);
    _memoryCache.remove(key);
    final tracked = _knownFormIdsByUser[cleanUid];
    if (tracked != null && tracked.remove(cleanForm)) {
      await _persistUserFormIndex(cleanUid, tracked);
    }
    await _vault.deleteSecret(key);
  }

  /// Clears ONLY in-memory draft caches (leaving encrypted vault records intact).
  static void clearAllInMemoryCaches() {
    _memoryCache.clear();
    _knownFormIdsByUser.clear();
  }

  /// Removes all persisted & cached form drafts belonging to [userId] without touching other users.
  static Future<void> clearAllDraftsForUser(String userId) async {
    final cleanUid = userId.trim();
    if (cleanUid.isEmpty) return;

    final formIds = <String>{
      ..._knownFormIds,
      ...?_knownFormIdsByUser[cleanUid],
      ...await _readUserFormIndex(cleanUid),
    };

    for (final formId in formIds) {
      final key = storageKey(userId: cleanUid, formId: formId);
      _memoryCache.remove(key);
      await _vault.deleteSecret(key);
    }
    _knownFormIdsByUser.remove(cleanUid);
    await _vault.deleteSecret(_indexKey(cleanUid));
  }

  static Future<Set<String>> _readUserFormIndex(String cleanUid) async {
    final raw = await _vault.readSecret(_indexKey(cleanUid));
    if (raw == null || raw.trim().isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet();
      }
    } catch (_) {
      // Ignore malformed index safely
    }
    return <String>{};
  }

  static Future<void> _persistUserFormIndex(
    String cleanUid,
    Set<String> formIds,
  ) async {
    final idxKey = _indexKey(cleanUid);
    if (formIds.isEmpty) {
      await _vault.deleteSecret(idxKey);
      return;
    }
    final existing = await _readUserFormIndex(cleanUid);
    final merged = <String>{...existing, ...formIds}.toList()..sort();
    await _vault.writeSecret(key: idxKey, value: jsonEncode(merged));
  }

  static Map<String, dynamic> _deepCloneMap(Map<String, dynamic> source) {
    final decoded = jsonDecode(jsonEncode(source));
    return Map<String, dynamic>.from(decoded as Map);
  }
}
