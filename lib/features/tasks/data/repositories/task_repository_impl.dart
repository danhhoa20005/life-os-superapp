import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../domain/entities/task_entities.dart';
import '../../domain/repositories/task_repository.dart';

class TaskRemoteDataSource {
  final FirebaseFirestore _firestore;
  static const Uuid _uuid = Uuid();

  const TaskRemoteDataSource(this._firestore);

  TaskEntity _mapTask(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String? familyId,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final dueRaw = d['dueAt'];
    final status = switch (d['status'] as String?) {
      'accepted' => TaskWorkflowStatus.accepted,
      'declined' => TaskWorkflowStatus.declined,
      'inProgress' => TaskWorkflowStatus.inProgress,
      'done' => TaskWorkflowStatus.done,
      _ => TaskWorkflowStatus.proposed,
    };
    final priority = switch (d['priority'] as String?) {
      'low' => TaskPriorityLevel.low,
      'high' => TaskPriorityLevel.high,
      _ => TaskPriorityLevel.medium,
    };
    final recurrence = switch (d['recurrence'] as String?) {
      'daily' => TaskRecurrence.daily,
      'weekly' => TaskRecurrence.weekly,
      'monthly' => TaskRecurrence.monthly,
      _ => TaskRecurrence.none,
    };

    return TaskEntity(
      id: (d['id'] as String?) ?? doc.id,
      familyId: familyId ?? (d['familyId'] as String?),
      createdBy: (d['createdBy'] as String?) ?? '',
      creatorName: (d['creatorName'] as String?) ?? 'Cá nhân',
      assigneeId: (d['assigneeId'] as String?) ?? '',
      assigneeName: (d['assigneeName'] as String?) ?? 'Cá nhân',
      title: (d['title'] as String?) ?? '',
      description: d['description'] as String?,
      dueAt: dueRaw is Timestamp ? dueRaw.toDate() : null,
      priority: priority,
      status: status,
      recurrence: recurrence,
      responseNote: d['responseNote'] as String?,
    );
  }

  Stream<List<TaskEntity>> watchTasks({
    required String userId,
    String? familyId,
  }) {
    final personalStream = _firestore
        .collection('users')
        .doc(userId)
        .collection('personal_tasks')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => _mapTask(d, null)).toList());

    if (familyId == null || familyId.isEmpty) {
      return personalStream;
    }

    final familyStream = _firestore
        .collection('families')
        .doc(familyId)
        .collection('tasks')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => _mapTask(d, familyId)).toList());

    return StreamCombiner.combine2(
      familyStream,
      personalStream,
      (fam, pers) => <TaskEntity>[...fam, ...pers],
    );
  }

  DocumentReference<Map<String, dynamic>> _taskRef(
    String userId,
    String? familyId,
    String taskId,
  ) {
    if (familyId == null || familyId.isEmpty) {
      return _firestore
          .collection('users')
          .doc(userId)
          .collection('personal_tasks')
          .doc(taskId);
    }
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('tasks')
        .doc(taskId);
  }

  Future<TaskEntity> createTask({
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
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    // Self-assigned task auto-accepts; task assigned to another family member starts as `proposed`!
    final initialStatus = createdBy == assigneeId
        ? TaskWorkflowStatus.accepted
        : TaskWorkflowStatus.proposed;

    final docRef = _taskRef(createdBy, familyId, id);
    await docRef.set({
      'id': id,
      'familyId': familyId,
      'createdBy': createdBy,
      'creatorName': creatorName,
      'assigneeId': assigneeId,
      'assigneeName': assigneeName,
      'title': title,
      'description': description,
      'dueAt': dueAt != null ? Timestamp.fromDate(dueAt) : null,
      'priority': priority.name,
      'status': initialStatus.name,
      'recurrence': recurrence.name,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });

    final snap = await docRef.get();
    return _mapTask(snap, familyId);
  }

  Future<void> respondToTask({
    required String actorUserId,
    required TaskEntity task,
    required bool accept,
    String? responseNote,
  }) async {
    final ref = _taskRef(actorUserId, task.familyId, task.id);
    await ref.update({
      'status': accept
          ? TaskWorkflowStatus.accepted.name
          : TaskWorkflowStatus.declined.name,
      if (responseNote != null) 'responseNote': responseNote,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> updateTaskStatus({
    required String actorUserId,
    required TaskEntity task,
    required TaskWorkflowStatus nextStatus,
  }) async {
    final now = DateTime.now();
    final batch = _firestore.batch();
    final ref = _taskRef(actorUserId, task.familyId, task.id);

    batch.update(ref, {
      'status': nextStatus.name,
      'updatedAt': Timestamp.fromDate(now),
    });

    if (nextStatus == TaskWorkflowStatus.done &&
        task.recurrence != TaskRecurrence.none) {
      final nextDue = TaskEntity.computeNextOccurrence(
        task.dueAt,
        task.recurrence,
      );
      final nextId = _uuid.v4();
      final nextRef = _taskRef(actorUserId, task.familyId, nextId);
      batch.set(nextRef, {
        'id': nextId,
        'familyId': task.familyId,
        'createdBy': task.createdBy,
        'creatorName': task.creatorName,
        'assigneeId': task.assigneeId,
        'assigneeName': task.assigneeName,
        'title': task.title,
        'description': task.description,
        'dueAt': nextDue != null ? Timestamp.fromDate(nextDue) : null,
        'priority': task.priority.name,
        'status': TaskWorkflowStatus.accepted.name,
        'recurrence': task.recurrence.name,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    }

    await batch.commit();
  }
}

class TaskRepositoryImpl implements TaskRepository {
  final TaskRemoteDataSource _remoteDataSource;
  const TaskRepositoryImpl(this._remoteDataSource);

  @override
  Stream<Result<List<TaskEntity>>> watchTasks({
    required String userId,
    String? familyId,
  }) {
    return _remoteDataSource
        .watchTasks(userId: userId, familyId: familyId)
        .map<Result<List<TaskEntity>>>((items) => Success(items))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<TaskEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
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
  }) async {
    try {
      final t = await _remoteDataSource.createTask(
        createdBy: createdBy,
        creatorName: creatorName,
        familyId: familyId,
        assigneeId: assigneeId,
        assigneeName: assigneeName,
        title: title,
        description: description,
        dueAt: dueAt,
        priority: priority,
        recurrence: recurrence,
      );
      return Success(t);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> respondToTask({
    required String actorUserId,
    required TaskEntity task,
    required bool accept,
    String? responseNote,
  }) async {
    try {
      await _remoteDataSource.respondToTask(
        actorUserId: actorUserId,
        task: task,
        accept: accept,
        responseNote: responseNote,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> updateTaskStatus({
    required String actorUserId,
    required TaskEntity task,
    required TaskWorkflowStatus nextStatus,
  }) async {
    try {
      await _remoteDataSource.updateTaskStatus(
        actorUserId: actorUserId,
        task: task,
        nextStatus: nextStatus,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
