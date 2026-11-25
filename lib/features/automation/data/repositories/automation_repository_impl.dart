import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/automation_entities.dart';
import '../../domain/repositories/automation_repository.dart';
import '../../domain/services/smart_automation_engine.dart';

class AutomationRepositoryImpl implements AutomationRepository {
  final FirebaseFirestore _firestore;

  const AutomationRepositoryImpl(this._firestore);

  CollectionReference<Map<String, dynamic>> _rulesCol(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('automation_rules');

  CollectionReference<Map<String, dynamic>> _auditsCol(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('automation_audits');

  @override
  Future<List<AutomationRuleEntity>> loadRules(String userId) async {
    final defaults = SmartAutomationEngine.defaultRulesForUser(userId);
    try {
      final snap = await _rulesCol(userId).get();
      if (snap.docs.isEmpty) {
        return defaults;
      }
      final overridesById = <String, Map<String, dynamic>>{
        for (final doc in snap.docs) doc.id: doc.data(),
      };
      return defaults.map((def) {
        final ov = overridesById[def.id];
        if (ov == null) return def;
        return def.copyWith(
          enabled: ov['enabled'] as bool? ?? def.enabled,
          requiresUserConfirmation:
              ov['requiresUserConfirmation'] as bool? ??
              def.requiresUserConfirmation,
          minAmountMinor:
              (ov['minAmountMinor'] as num?)?.toInt() ?? def.minAmountMinor,
          thresholdPct:
              (ov['thresholdPct'] as num?)?.toInt() ?? def.thresholdPct,
          leadDays: (ov['leadDays'] as num?)?.toInt() ?? def.leadDays,
        );
      }).toList();
    } catch (_) {
      return defaults;
    }
  }

  @override
  Future<void> saveRule(AutomationRuleEntity rule) async {
    await _rulesCol(rule.ownerId).doc(rule.id).set(<String, dynamic>{
      'id': rule.id,
      'ownerId': rule.ownerId,
      'nameVi': rule.nameVi,
      'descriptionVi': rule.descriptionVi,
      'triggerCode': rule.triggerKind.code,
      'actionCode': rule.actionKind.code,
      'enabled': rule.enabled,
      'requiresUserConfirmation': rule.requiresUserConfirmation,
      'minAmountMinor': rule.minAmountMinor,
      'thresholdPct': rule.thresholdPct,
      'leadDays': rule.leadDays,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<List<AutomationAuditEntry>> loadAuditLog(String userId) async {
    try {
      final snap = await _auditsCol(userId)
          .orderBy('timestampEpochMs', descending: true)
          .limit(60)
          .get();
      return snap.docs.map((d) => _auditFromMap(d.data())).toList();
    } catch (_) {
      return const <AutomationAuditEntry>[];
    }
  }

  @override
  Future<void> appendAuditEntries(
    String userId,
    List<AutomationAuditEntry> entries,
  ) async {
    if (entries.isEmpty) return;
    final batch = _firestore.batch();
    for (final entry in entries) {
      batch.set(_auditsCol(userId).doc(entry.auditId), <String, dynamic>{
        'auditId': entry.auditId,
        'idempotencyKey': entry.idempotencyKey,
        'ruleId': entry.ruleId,
        'sourceEventId': entry.sourceEventId,
        'actorUserId': entry.actorUserId,
        'actionCode': entry.actionKind.code,
        'status': entry.status.name,
        'summaryVi': entry.summaryVi,
        'timestampEpochMs': entry.timestamp.millisecondsSinceEpoch,
        if (entry.undoReferenceId != null)
          'undoReferenceId': entry.undoReferenceId,
      });
    }
    await batch.commit();
  }

  @override
  Future<AutomationAuditEntry?> undoAuditEntry(
    String userId,
    String auditId,
    DateTime undoneAt,
  ) async {
    final docRef = _auditsCol(userId).doc(auditId);
    final doc = await docRef.get();
    final data = doc.data();
    if (data == null) return null;
    final current = _auditFromMap(data);
    final updated = current.markUndone(undoneAt);
    await docRef.set(<String, dynamic>{
      'status': updated.status.name,
      'summaryVi': updated.summaryVi,
      'timestampEpochMs': updated.timestamp.millisecondsSinceEpoch,
    }, SetOptions(merge: true));
    return updated;
  }

  AutomationAuditEntry _auditFromMap(Map<String, dynamic> map) {
    final actionCode = (map['actionCode'] ?? '').toString();
    final action = AutomationActionKind.values.firstWhere(
      (a) => a.code == actionCode,
      orElse: () => AutomationActionKind.emitSpendingAlert,
    );
    final statusName = (map['status'] ?? '').toString();
    final status = AutomationAuditStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => AutomationAuditStatus.suggested,
    );
    final ms = (map['timestampEpochMs'] as num?)?.toInt() ?? 0;
    return AutomationAuditEntry(
      auditId: (map['auditId'] ?? '').toString(),
      idempotencyKey: (map['idempotencyKey'] ?? '').toString(),
      ruleId: (map['ruleId'] ?? '').toString(),
      sourceEventId: (map['sourceEventId'] ?? '').toString(),
      actorUserId: (map['actorUserId'] ?? '').toString(),
      actionKind: action,
      status: status,
      summaryVi: (map['summaryVi'] ?? '').toString(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(ms),
      undoReferenceId: map['undoReferenceId']?.toString(),
    );
  }
}
