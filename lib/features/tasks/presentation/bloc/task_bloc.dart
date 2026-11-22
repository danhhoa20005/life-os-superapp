import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/task_entities.dart';
import '../../domain/repositories/task_repository.dart';

sealed class TaskEvent extends Equatable {
  const TaskEvent();

  @override
  List<Object?> get props => [];
}

final class TasksWatchStarted extends TaskEvent {
  final String userId;
  final String? familyId;

  const TasksWatchStarted({required this.userId, this.familyId});

  @override
  List<Object?> get props => [userId, familyId];
}

final class TaskCreateSubmitted extends TaskEvent {
  final CreateTaskParams params;
  const TaskCreateSubmitted(this.params);

  @override
  List<Object?> get props => [params];
}

final class TaskResponseSubmitted extends TaskEvent {
  final RespondToTaskParams params;
  const TaskResponseSubmitted(this.params);

  @override
  List<Object?> get props => [params];
}

final class TaskStatusChanged extends TaskEvent {
  final String actorUserId;
  final TaskEntity task;
  final TaskWorkflowStatus nextStatus;

  const TaskStatusChanged({
    required this.actorUserId,
    required this.task,
    required this.nextStatus,
  });

  @override
  List<Object?> get props => [actorUserId, task, nextStatus];
}

final class TaskState extends Equatable {
  final bool isLoading;
  final List<TaskEntity> tasks;
  final Failure? failure;
  final String? message;

  const TaskState({
    this.isLoading = false,
    this.tasks = const [],
    this.failure,
    this.message,
  });

  TaskState copyWith({
    bool? isLoading,
    List<TaskEntity>? tasks,
    Failure? failure,
    bool clearFailure = false,
    String? message,
    bool clearMessage = false,
  }) {
    return TaskState(
      isLoading: isLoading ?? this.isLoading,
      tasks: tasks != null ? List.unmodifiable(tasks) : this.tasks,
      failure: clearFailure ? null : (failure ?? this.failure),
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [isLoading, tasks, failure, message];
}

class TaskBloc extends Bloc<TaskEvent, TaskState> {
  final TaskRepository _repository;
  final CreateTaskUseCase _createTask;
  final RespondToTaskUseCase _respondToTask;

  TaskBloc({
    required TaskRepository repository,
    required CreateTaskUseCase createTask,
    required RespondToTaskUseCase respondToTask,
  })  : _repository = repository,
        _createTask = createTask,
        _respondToTask = respondToTask,
        super(const TaskState()) {
    on<TasksWatchStarted>(_onWatchStarted, transformer: restartable());
    on<TaskCreateSubmitted>(_onCreateTask, transformer: sequential());
    on<TaskResponseSubmitted>(_onRespondTask, transformer: sequential());
    on<TaskStatusChanged>(_onStatusChanged, transformer: sequential());
  }

  Future<void> _onWatchStarted(
    TasksWatchStarted event,
    Emitter<TaskState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));
    await emit.forEach<Result<List<TaskEntity>>>(
      _repository.watchTasks(userId: event.userId, familyId: event.familyId),
      onData: (res) => res.fold(
        (f) => state.copyWith(isLoading: false, failure: f),
        (items) => state.copyWith(isLoading: false, tasks: items, clearFailure: true),
      ),
    );
  }

  Future<void> _onCreateTask(
    TaskCreateSubmitted event,
    Emitter<TaskState> emit,
  ) async {
    final res = await _createTask(event.params);
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(message: 'Đã tạo công việc mới.')),
    );
  }

  Future<void> _onRespondTask(
    TaskResponseSubmitted event,
    Emitter<TaskState> emit,
  ) async {
    final res = await _respondToTask(event.params);
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          message: event.params.accept ? 'Đã nhận nhiệm vụ.' : 'Đã từ chối nhiệm vụ.',
        ),
      ),
    );
  }

  Future<void> _onStatusChanged(
    TaskStatusChanged event,
    Emitter<TaskState> emit,
  ) async {
    final res = await _repository.updateTaskStatus(
      actorUserId: event.actorUserId,
      task: event.task,
      nextStatus: event.nextStatus,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          message: event.nextStatus == TaskWorkflowStatus.done &&
                  event.task.recurrence != TaskRecurrence.none
              ? 'Đã hoàn thành và tự động tạo kỳ lặp tiếp theo.'
              : 'Đã cập nhật tiến độ công việc.',
        ),
      ),
    );
  }
}
