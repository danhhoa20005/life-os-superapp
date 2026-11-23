import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/task_entities.dart';

abstract interface class TaskRepository {
  Stream<Result<List<TaskEntity>>> watchTasks({
    required String userId,
    String? familyId,
  });

  Future<Result<TaskEntity>> createTask({
    required String createdBy,
    required String creatorName,
    String? familyId,
    required String assigneeId,
    required String assigneeName,
    required String title,
    String? description,
    DateTime? dueAt,
    required TaskPriorityLevel priority,
    required TaskRecurrence recurrence,
  });

  Future<Result<void>> respondToTask({
    required String actorUserId,
    required TaskEntity task,
    required bool accept,
    String? responseNote,
  });

  Future<Result<void>> updateTaskStatus({
    required String actorUserId,
    required TaskEntity task,
    required TaskWorkflowStatus nextStatus,
  });
}

final class CreateTaskParams {
  final String createdBy;
  final String creatorName;
  final String? familyId;
  final String assigneeId;
  final String assigneeName;
  final String title;
  final String? description;
  final DateTime? dueAt;
  final TaskPriorityLevel priority;
  final TaskRecurrence recurrence;

  const CreateTaskParams({
    required this.createdBy,
    required this.creatorName,
    this.familyId,
    required this.assigneeId,
    required this.assigneeName,
    required this.title,
    this.description,
    this.dueAt,
    this.priority = TaskPriorityLevel.medium,
    this.recurrence = TaskRecurrence.none,
  });
}

class CreateTaskUseCase implements UseCase<TaskEntity, CreateTaskParams> {
  final TaskRepository _repository;
  const CreateTaskUseCase(this._repository);

  @override
  Future<Result<TaskEntity>> call(CreateTaskParams params) async {
    if (params.title.trim().length < 2) {
      return const Err(
        ValidationFailure(message: 'Tên công việc phải có ít nhất 2 ký tự.'),
      );
    }
    return _repository.createTask(
      createdBy: params.createdBy,
      creatorName: params.creatorName,
      familyId: params.familyId,
      assigneeId: params.assigneeId,
      assigneeName: params.assigneeName,
      title: params.title.trim(),
      description: params.description?.trim(),
      dueAt: params.dueAt,
      priority: params.priority,
      recurrence: params.recurrence,
    );
  }
}

final class RespondToTaskParams {
  final String actorUserId;
  final TaskEntity task;
  final bool accept;
  final String? responseNote;

  const RespondToTaskParams({
    required this.actorUserId,
    required this.task,
    required this.accept,
    this.responseNote,
  });
}

class RespondToTaskUseCase implements UseCase<void, RespondToTaskParams> {
  final TaskRepository _repository;
  const RespondToTaskUseCase(this._repository);

  @override
  Future<Result<void>> call(RespondToTaskParams params) async {
    // Domain invariant (Section 7.2): Only the assigned recipient can accept or decline a task!
    if (params.actorUserId != params.task.assigneeId) {
      return const Err(
        PermissionDeniedFailure(
          message:
              'Chỉ người được giao việc mới có quyền chấp nhận hoặc từ chối nhiệm vụ.',
        ),
      );
    }
    return _repository.respondToTask(
      actorUserId: params.actorUserId,
      task: params.task,
      accept: params.accept,
      responseNote: params.responseNote?.trim(),
    );
  }
}
