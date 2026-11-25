import 'package:equatable/equatable.dart';

import '../entities/automation_entities.dart';

abstract interface class AutomationRepository {
  Future<List<AutomationRuleEntity>> loadRules(String userId);
  Future<void> saveRule(AutomationRuleEntity rule);
  Future<List<AutomationAuditEntry>> loadAuditLog(String userId);
  Future<void> appendAuditEntries(
    String userId,
    List<AutomationAuditEntry> entries,
  );
  Future<AutomationAuditEntry?> undoAuditEntry(
    String userId,
    String auditId,
    DateTime undoneAt,
  );
}

class AutomationSnapshot extends Equatable {
  final List<AutomationRuleEntity> rules;
  final List<AutomationAuditEntry> audits;
  final List<AutomationActionSuggestion> pendingSuggestions;

  const AutomationSnapshot({
    required this.rules,
    required this.audits,
    this.pendingSuggestions = const <AutomationActionSuggestion>[],
  });

  @override
  List<Object?> get props => [rules, audits, pendingSuggestions];
}
