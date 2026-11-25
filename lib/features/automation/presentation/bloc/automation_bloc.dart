import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../domain/entities/automation_entities.dart';
import '../../domain/repositories/automation_repository.dart';
import '../../domain/services/smart_automation_engine.dart';

sealed class AutomationEvent extends Equatable {
  const AutomationEvent();

  @override
  List<Object?> get props => const [];
}

final class AutomationStarted extends AutomationEvent {
  final String userId;
  const AutomationStarted(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class AutomationRuleToggled extends AutomationEvent {
  final String ruleId;
  final bool enabled;

  const AutomationRuleToggled({required this.ruleId, required this.enabled});

  @override
  List<Object?> get props => [ruleId, enabled];
}

final class AutomationDomainEventDispatched extends AutomationEvent {
  final AutomationDomainEvent domainEvent;
  final Set<String> allowedFamilyIds;

  const AutomationDomainEventDispatched({
    required this.domainEvent,
    this.allowedFamilyIds = const <String>{},
  });

  @override
  List<Object?> get props => [domainEvent, allowedFamilyIds];
}

final class AutomationSuggestionConfirmed extends AutomationEvent {
  final AutomationActionSuggestion suggestion;
  const AutomationSuggestionConfirmed(this.suggestion);

  @override
  List<Object?> get props => [suggestion];
}

final class AutomationSuggestionDismissed extends AutomationEvent {
  final String suggestionId;
  const AutomationSuggestionDismissed(this.suggestionId);

  @override
  List<Object?> get props => [suggestionId];
}

final class AutomationAuditUndoRequested extends AutomationEvent {
  final String auditId;
  const AutomationAuditUndoRequested(this.auditId);

  @override
  List<Object?> get props => [auditId];
}

class AutomationState extends Equatable {
  final String? userId;
  final bool isLoading;
  final List<AutomationRuleEntity> rules;
  final List<AutomationActionSuggestion> suggestions;
  final List<AutomationAuditEntry> audits;
  final String? feedbackMessage;

  const AutomationState({
    this.userId,
    this.isLoading = false,
    this.rules = const <AutomationRuleEntity>[],
    this.suggestions = const <AutomationActionSuggestion>[],
    this.audits = const <AutomationAuditEntry>[],
    this.feedbackMessage,
  });

  AutomationState copyWith({
    String? userId,
    bool? isLoading,
    List<AutomationRuleEntity>? rules,
    List<AutomationActionSuggestion>? suggestions,
    List<AutomationAuditEntry>? audits,
    String? feedbackMessage,
    bool clearMessage = false,
  }) {
    return AutomationState(
      userId: userId ?? this.userId,
      isLoading: isLoading ?? this.isLoading,
      rules: rules ?? this.rules,
      suggestions: suggestions ?? this.suggestions,
      audits: audits ?? this.audits,
      feedbackMessage: clearMessage
          ? null
          : (feedbackMessage ?? this.feedbackMessage),
    );
  }

  @override
  List<Object?> get props => [
    userId,
    isLoading,
    rules,
    suggestions,
    audits,
    feedbackMessage,
  ];
}

class AutomationBloc extends Bloc<AutomationEvent, AutomationState> {
  final AutomationRepository _repository;

  AutomationBloc({required AutomationRepository repository})
    : _repository = repository,
      super(const AutomationState()) {
    on<AutomationStarted>(_onStarted, transformer: restartable());
    on<AutomationRuleToggled>(_onRuleToggled, transformer: sequential());
    on<AutomationDomainEventDispatched>(
      _onDomainEventDispatched,
      transformer: sequential(),
    );
    on<AutomationSuggestionConfirmed>(
      _onSuggestionConfirmed,
      transformer: sequential(),
    );
    on<AutomationSuggestionDismissed>(_onSuggestionDismissed);
    on<AutomationAuditUndoRequested>(
      _onUndoRequested,
      transformer: sequential(),
    );
  }

  Future<void> _onStarted(
    AutomationStarted event,
    Emitter<AutomationState> emit,
  ) async {
    emit(
      state.copyWith(userId: event.userId, isLoading: true, clearMessage: true),
    );
    final rules = await _repository.loadRules(event.userId);
    final audits = await _repository.loadAuditLog(event.userId);
    emit(state.copyWith(isLoading: false, rules: rules, audits: audits));
  }

  Future<void> _onRuleToggled(
    AutomationRuleToggled event,
    Emitter<AutomationState> emit,
  ) async {
    final idx = state.rules.indexWhere((r) => r.id == event.ruleId);
    if (idx < 0) return;
    final updated = state.rules[idx].copyWith(enabled: event.enabled);
    final nextRules = List<AutomationRuleEntity>.from(state.rules)
      ..[idx] = updated;
    await _repository.saveRule(updated);
    emit(
      state.copyWith(
        rules: nextRules,
        feedbackMessage: event.enabled
            ? 'Đã bật quy tắc "${updated.nameVi}".'
            : 'Đã tạm tắt quy tắc "${updated.nameVi}".',
      ),
    );
  }

  Future<void> _onDomainEventDispatched(
    AutomationDomainEventDispatched event,
    Emitter<AutomationState> emit,
  ) async {
    final uid = state.userId ?? event.domainEvent.actorUserId;
    final rules = state.rules.isNotEmpty
        ? state.rules
        : await _repository.loadRules(uid);
    final processedKeys = <String>{
      for (final a in state.audits)
        if (a.status == AutomationAuditStatus.executed ||
            a.status == AutomationAuditStatus.suggested)
          a.idempotencyKey,
    };
    final batch = SmartAutomationEngine.evaluate(
      event: event.domainEvent,
      rules: rules,
      activeUserId: uid,
      allowedFamilyIds: event.allowedFamilyIds,
      processedIdempotencyKeys: processedKeys,
    );
    await _repository.appendAuditEntries(uid, batch.audits);
    emit(
      state.copyWith(
        userId: uid,
        rules: rules,
        suggestions: [...batch.suggestions, ...state.suggestions],
        audits: [...batch.audits, ...state.audits],
      ),
    );
  }

  Future<void> _onSuggestionConfirmed(
    AutomationSuggestionConfirmed event,
    Emitter<AutomationState> emit,
  ) async {
    final uid = state.userId;
    if (uid == null) return;
    final execAudit = AutomationAuditEntry(
      auditId: 'aud_exec_${event.suggestion.idempotencyKey}',
      idempotencyKey: event.suggestion.idempotencyKey,
      ruleId: event.suggestion.ruleId,
      sourceEventId: event.suggestion.sourceEventId,
      actorUserId: uid,
      actionKind: event.suggestion.actionKind,
      status: AutomationAuditStatus.executed,
      summaryVi: 'Đã xác nhận: ${event.suggestion.headlineVi}',
      timestamp: DateTime.now(),
      undoReferenceId: event.suggestion.suggestionId,
    );
    await _repository.appendAuditEntries(uid, [execAudit]);
    emit(
      state.copyWith(
        suggestions: state.suggestions
            .where((s) => s.suggestionId != event.suggestion.suggestionId)
            .toList(),
        audits: [execAudit, ...state.audits],
        feedbackMessage: 'Đã thực hiện "${event.suggestion.headlineVi}".',
      ),
    );
  }

  void _onSuggestionDismissed(
    AutomationSuggestionDismissed event,
    Emitter<AutomationState> emit,
  ) {
    emit(
      state.copyWith(
        suggestions: state.suggestions
            .where((s) => s.suggestionId != event.suggestionId)
            .toList(),
        clearMessage: true,
      ),
    );
  }

  Future<void> _onUndoRequested(
    AutomationAuditUndoRequested event,
    Emitter<AutomationState> emit,
  ) async {
    final uid = state.userId;
    if (uid == null) return;
    final undone = await _repository.undoAuditEntry(
      uid,
      event.auditId,
      DateTime.now(),
    );
    if (undone == null) return;
    final nextAudits = state.audits
        .map((a) => a.auditId == event.auditId ? undone : a)
        .toList();
    emit(
      state.copyWith(
        audits: nextAudits,
        feedbackMessage: 'Đã hoàn tác hành động tự động hóa.',
      ),
    );
  }
}
