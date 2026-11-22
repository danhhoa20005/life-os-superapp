import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/calendar_entities.dart';

abstract interface class CalendarRepository {
  Stream<Result<List<CalendarEventEntity>>> watchEvents({
    required String userId,
    String? familyId,
  });

  Stream<Result<List<BusySlotEntity>>> watchFamilyBusySlots(String familyId);

  Future<Result<CalendarEventEntity>> createEvent({
    required String userId,
    required String userName,
    String? familyId,
    required CalendarEventVisibility visibility,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    required bool publishBusySlot,
  });

  Future<Result<void>> deleteEvent({
    required String userId,
    String? familyId,
    required CalendarEventVisibility visibility,
    required String eventId,
  });
}

final class CreateCalendarEventParams {
  final String userId;
  final String userName;
  final String? familyId;
  final CalendarEventVisibility visibility;
  final String title;
  final String? description;
  final String? location;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool publishBusySlot;

  const CreateCalendarEventParams({
    required this.userId,
    required this.userName,
    this.familyId,
    required this.visibility,
    required this.title,
    this.description,
    this.location,
    required this.startsAt,
    required this.endsAt,
    this.publishBusySlot = false,
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
      familyId: params.familyId,
      visibility: params.visibility,
      title: params.title.trim(),
      description: params.description?.trim(),
      location: params.location?.trim(),
      startsAt: params.startsAt,
      endsAt: params.endsAt,
      publishBusySlot: params.publishBusySlot,
    );
  }
}
