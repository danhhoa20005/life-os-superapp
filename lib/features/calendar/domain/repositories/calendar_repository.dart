import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/calendar_entities.dart';

abstract interface class CalendarRepository {
  Stream<Result<List<ManagedCalendarEntity>>> watchCalendars(String userId);

  Future<Result<ManagedCalendarEntity>> createCalendar({
    required String userId,
    required String summary,
    String? description,
    String colorHex = '#0B7A2A',
    bool createOnGoogle = false,
  });

  Future<Result<ManagedCalendarEntity>> updateCalendar({
    required String userId,
    required ManagedCalendarEntity calendar,
  });

  Future<Result<void>> deleteCalendar({
    required String userId,
    required ManagedCalendarEntity calendar,
  });

  Stream<Result<List<CalendarEventEntity>>> watchEvents({
    required String userId,
    String? familyId,
  });

  Stream<Result<List<BusySlotEntity>>> watchFamilyBusySlots(String familyId);

  Future<Result<CalendarEventEntity>> createEvent({
    required String userId,
    required String userName,
    String calendarId = 'primary',
    String? familyId,
    required CalendarEventVisibility visibility,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool isAllDay = false,
    String? colorHex,
    int reminderMinutesBefore = 30,
    CalendarRecurrenceRule recurrence = CalendarRecurrenceRule.none,
    required bool publishBusySlot,
    bool syncToGoogle = false,
  });

  Future<Result<CalendarEventEntity>> updateEvent({
    required String userId,
    required String userName,
    required CalendarEventEntity existingEvent,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool? isAllDay,
    String? calendarId,
    String? colorHex,
    int? reminderMinutesBefore,
    CalendarRecurrenceRule? recurrence,
    bool publishBusySlot = false,
    bool syncToGoogle = false,
  });

  Future<Result<void>> deleteEvent({
    required String userId,
    String? familyId,
    required CalendarEventVisibility visibility,
    required String eventId,
    String? googleCalendarId,
    String? googleEventId,
  });

  Future<Result<GoogleCalendarSyncReport>> syncWithGoogleCalendar({
    required String userId,
    required String userName,
    bool interactivePromptIfNeeded = true,
    String? manualAccessTokenOverride,
  });

  bool get isGoogleCalendarAuthorized;
}

final class CreateManagedCalendarParams {
  final String userId;
  final String summary;
  final String? description;
  final String colorHex;
  final bool createOnGoogle;

  const CreateManagedCalendarParams({
    required this.userId,
    required this.summary,
    this.description,
    this.colorHex = '#0B7A2A',
    this.createOnGoogle = false,
  });
}

class CreateManagedCalendarUseCase
    implements UseCase<ManagedCalendarEntity, CreateManagedCalendarParams> {
  final CalendarRepository _repository;
  const CreateManagedCalendarUseCase(this._repository);

  @override
  Future<Result<ManagedCalendarEntity>> call(CreateManagedCalendarParams params) async {
    final clean = params.summary.trim();
    if (clean.length < 2) {
      return const Err(ValidationFailure(message: 'Tên bộ lịch phải có ít nhất 2 ký tự.'));
    }
    return _repository.createCalendar(
      userId: params.userId,
      summary: clean,
      description: params.description?.trim(),
      colorHex: params.colorHex,
      createOnGoogle: params.createOnGoogle,
    );
  }
}

final class CreateCalendarEventParams {
  final String userId;
  final String userName;
  final String calendarId;
  final String? familyId;
  final CalendarEventVisibility visibility;
  final String title;
  final String? description;
  final String? location;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isAllDay;
  final String? colorHex;
  final int reminderMinutesBefore;
  final CalendarRecurrenceRule recurrence;
  final bool publishBusySlot;
  final bool syncToGoogle;

  const CreateCalendarEventParams({
    required this.userId,
    required this.userName,
    this.calendarId = 'primary',
    this.familyId,
    required this.visibility,
    required this.title,
    this.description,
    this.location,
    required this.startsAt,
    required this.endsAt,
    this.isAllDay = false,
    this.colorHex,
    this.reminderMinutesBefore = 30,
    this.recurrence = CalendarRecurrenceRule.none,
    this.publishBusySlot = false,
    this.syncToGoogle = false,
  });
}

class CreateCalendarEventUseCase
    implements UseCase<CalendarEventEntity, CreateCalendarEventParams> {
  final CalendarRepository _repository;
  const CreateCalendarEventUseCase(this._repository);

  @override
  Future<Result<CalendarEventEntity>> call(CreateCalendarEventParams params) async {
    if (params.title.trim().length < 2) {
      return const Err(ValidationFailure(message: 'Tiêu đề sự kiện phải có ít nhất 2 ký tự.'));
    }
    if (params.endsAt.isBefore(params.startsAt)) {
      return const Err(
        ValidationFailure(message: 'Thời gian kết thúc không được trước thời gian bắt đầu.'),
      );
    }
    if (params.visibility == CalendarEventVisibility.sharedEvent &&
        (params.familyId == null || params.familyId!.isEmpty)) {
      return const Err(
        ValidationFailure(message: 'Sự kiện lịch chung cần chọn hộ gia đình.'),
      );
    }
    return _repository.createEvent(
      userId: params.userId,
      userName: params.userName,
      calendarId: params.calendarId,
      familyId: params.familyId,
      visibility: params.visibility,
      title: params.title.trim(),
      description: params.description?.trim(),
      location: params.location?.trim(),
      startsAt: params.startsAt,
      endsAt: params.endsAt,
      isAllDay: params.isAllDay,
      colorHex: params.colorHex,
      reminderMinutesBefore: params.reminderMinutesBefore,
      recurrence: params.recurrence,
      publishBusySlot: params.publishBusySlot,
      syncToGoogle: params.syncToGoogle,
    );
  }
}

final class UpdateCalendarEventParams {
  final String userId;
  final String userName;
  final CalendarEventEntity existingEvent;
  final String title;
  final String? description;
  final String? location;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool? isAllDay;
  final String? calendarId;
  final String? colorHex;
  final int? reminderMinutesBefore;
  final CalendarRecurrenceRule? recurrence;
  final bool publishBusySlot;
  final bool syncToGoogle;

  const UpdateCalendarEventParams({
    required this.userId,
    required this.userName,
    required this.existingEvent,
    required this.title,
    this.description,
    this.location,
    required this.startsAt,
    required this.endsAt,
    this.isAllDay,
    this.calendarId,
    this.colorHex,
    this.reminderMinutesBefore,
    this.recurrence,
    this.publishBusySlot = false,
    this.syncToGoogle = false,
  });
}

class UpdateCalendarEventUseCase
    implements UseCase<CalendarEventEntity, UpdateCalendarEventParams> {
  final CalendarRepository _repository;
  const UpdateCalendarEventUseCase(this._repository);

  @override
  Future<Result<CalendarEventEntity>> call(UpdateCalendarEventParams params) async {
    if (params.title.trim().length < 2) {
      return const Err(ValidationFailure(message: 'Tiêu đề sự kiện phải có ít nhất 2 ký tự.'));
    }
    if (params.endsAt.isBefore(params.startsAt)) {
      return const Err(
        ValidationFailure(message: 'Thời gian kết thúc không được trước thời gian bắt đầu.'),
      );
    }
    return _repository.updateEvent(
      userId: params.userId,
      userName: params.userName,
      existingEvent: params.existingEvent,
      title: params.title.trim(),
      description: params.description?.trim(),
      location: params.location?.trim(),
      startsAt: params.startsAt,
      endsAt: params.endsAt,
      isAllDay: params.isAllDay,
      calendarId: params.calendarId,
      colorHex: params.colorHex,
      reminderMinutesBefore: params.reminderMinutesBefore,
      recurrence: params.recurrence,
      publishBusySlot: params.publishBusySlot,
      syncToGoogle: params.syncToGoogle,
    );
  }
}

final class SyncGoogleCalendarParams {
  final String userId;
  final String userName;
  final bool interactivePromptIfNeeded;
  final String? manualAccessTokenOverride;

  const SyncGoogleCalendarParams({
    required this.userId,
    required this.userName,
    this.interactivePromptIfNeeded = true,
    this.manualAccessTokenOverride,
  });
}

class SyncGoogleCalendarUseCase
    implements UseCase<GoogleCalendarSyncReport, SyncGoogleCalendarParams> {
  final CalendarRepository _repository;
  const SyncGoogleCalendarUseCase(this._repository);

  @override
  Future<Result<GoogleCalendarSyncReport>> call(SyncGoogleCalendarParams params) {
    return _repository.syncWithGoogleCalendar(
      userId: params.userId,
      userName: params.userName,
      interactivePromptIfNeeded: params.interactivePromptIfNeeded,
      manualAccessTokenOverride: params.manualAccessTokenOverride,
    );
  }
}
