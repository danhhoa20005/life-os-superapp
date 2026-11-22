import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/calendar_entities.dart';
import '../../domain/repositories/calendar_repository.dart';

sealed class CalendarEvent extends Equatable {
  const CalendarEvent();

  @override
  List<Object?> get props => [];
}

final class CalendarWatchStarted extends CalendarEvent {
  final String userId;
  final String? familyId;

  const CalendarWatchStarted({required this.userId, this.familyId});

  @override
  List<Object?> get props => [userId, familyId];
}

final class CalendarEventCreated extends CalendarEvent {
  final CreateCalendarEventParams params;
  const CalendarEventCreated(this.params);

  @override
  List<Object?> get props => [params];
}

final class CalendarEventDeleted extends CalendarEvent {
  final String userId;
  final String? familyId;
  final CalendarEventVisibility visibility;
  final String eventId;

  const CalendarEventDeleted({
    required this.userId,
    this.familyId,
    required this.visibility,
    required this.eventId,
  });

  @override
  List<Object?> get props => [userId, familyId, visibility, eventId];
}

final class CalendarState extends Equatable {
  final bool isLoading;
  final List<CalendarEventEntity> events;
  final Failure? failure;
  final String? message;

  const CalendarState({
    this.isLoading = false,
    this.events = const [],
    this.failure,
    this.message,
  });

  CalendarState copyWith({
    bool? isLoading,
    List<CalendarEventEntity>? events,
    Failure? failure,
    bool clearFailure = false,
    String? message,
    bool clearMessage = false,
  }) {
    return CalendarState(
      isLoading: isLoading ?? this.isLoading,
      events: events != null ? List.unmodifiable(events) : this.events,
      failure: clearFailure ? null : (failure ?? this.failure),
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [isLoading, events, failure, message];
}

class CalendarBloc extends Bloc<CalendarEvent, CalendarState> {
  final CalendarRepository _repository;
  final CreateCalendarEventUseCase _createEvent;

  CalendarBloc({
    required CalendarRepository repository,
    required CreateCalendarEventUseCase createEvent,
  })  : _repository = repository,
        _createEvent = createEvent,
        super(const CalendarState()) {
    on<CalendarWatchStarted>(_onWatchStarted, transformer: restartable());
    on<CalendarEventCreated>(_onEventCreated, transformer: sequential());
    on<CalendarEventDeleted>(_onEventDeleted, transformer: sequential());
  }

  Future<void> _onWatchStarted(
    CalendarWatchStarted event,
    Emitter<CalendarState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));
    await emit.forEach<Result<List<CalendarEventEntity>>>(
      _repository.watchEvents(userId: event.userId, familyId: event.familyId),
      onData: (res) => res.fold(
        (f) => state.copyWith(isLoading: false, failure: f),
        (items) => state.copyWith(isLoading: false, events: items, clearFailure: true),
      ),
    );
  }

  Future<void> _onEventCreated(
    CalendarEventCreated event,
    Emitter<CalendarState> emit,
  ) async {
    final res = await _createEvent(event.params);
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (ev) => emit(
        state.copyWith(
          message: ev.visibility == CalendarEventVisibility.privateEvent
              ? 'Đã lưu sự kiện riêng tư (chỉ mình bạn xem được).'
              : 'Đã chia sẻ sự kiện lên lịch gia đình.',
        ),
      ),
    );
  }

  Future<void> _onEventDeleted(
    CalendarEventDeleted event,
    Emitter<CalendarState> emit,
  ) async {
    final res = await _repository.deleteEvent(
      userId: event.userId,
      familyId: event.familyId,
      visibility: event.visibility,
      eventId: event.eventId,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(message: 'Đã xóa sự kiện.')),
    );
  }
}
