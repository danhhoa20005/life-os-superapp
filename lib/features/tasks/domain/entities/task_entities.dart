import 'package:equatable/equatable.dart';

enum TaskWorkflowStatus { proposed, accepted, declined, inProgress, done }

enum TaskRecurrence { none, daily, weekly, monthly }

enum TaskPriorityLevel { low, medium, high }

class TaskEntity extends Equatable {
  final String id;
  final String? familyId;
  final String createdBy;
  final String creatorName;
  final String assigneeId;
  final String assigneeName;
  final String title;
  final String? description;
  final DateTime? dueAt;
  final TaskPriorityLevel priority;
  final TaskWorkflowStatus status;
  final TaskRecurrence recurrence;
  final String? responseNote;

  const TaskEntity({
    required this.id,
    this.familyId,
    required this.createdBy,
    required this.creatorName,
    required this.assigneeId,
    required this.assigneeName,
    required this.title,
    this.description,
    this.dueAt,
    this.priority = TaskPriorityLevel.medium,
    required this.status,
    this.recurrence = TaskRecurrence.none,
    this.responseNote,
  });

  bool get isPersonal => familyId == null || familyId!.isEmpty;

  /// Computes next due date for recurring tasks cleanly in pure Dart.
  static DateTime? computeNextOccurrence(
    DateTime? currentDue,
    TaskRecurrence recurrence,
  ) {
    if (recurrence == TaskRecurrence.none) return null;
    final base = currentDue ?? DateTime.now();
    return switch (recurrence) {
      TaskRecurrence.daily => base.add(const Duration(days: 1)),
      TaskRecurrence.weekly => base.add(const Duration(days: 7)),
      TaskRecurrence.monthly => DateTime(
        base.year,
        base.month + 1,
        base.day,
        base.hour,
        base.minute,
      ),
      TaskRecurrence.none => null,
    };
  }

  @override
  List<Object?> get props => [
    id,
    familyId,
    createdBy,
    creatorName,
    assigneeId,
    assigneeName,
    title,
    description,
    dueAt,
    priority,
    status,
    recurrence,
    responseNote,
  ];
}
