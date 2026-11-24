import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/services/native_alarm_scheduler_bridge.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../../../core/utils/vietnamese_search_matcher.dart';
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

final class CalendarFilterSelected extends CalendarEvent {
  final String? calendarId;
  const CalendarFilterSelected(this.calendarId);

  @override
  List<Object?> get props => [calendarId];
}

final class CalendarSearchChanged extends CalendarEvent {
  final String query;
  const CalendarSearchChanged(this.query);

  @override
  List<Object?> get props => [query];
}

final class CalendarFiltersReset extends CalendarEvent {
  final String? userId;
  final bool enableHiddenUserCalendars;

  const CalendarFiltersReset({
    this.userId,
    this.enableHiddenUserCalendars = true,
  });

  @override
  List<Object?> get props => [userId, enableHiddenUserCalendars];
}

final class ManagedCalendarCreateSubmitted extends CalendarEvent {
  final CreateManagedCalendarParams params;
  const ManagedCalendarCreateSubmitted(this.params);

  @override
  List<Object?> get props => [params];
}

final class ManagedCalendarVisibilityToggled extends CalendarEvent {
  final String userId;
  final ManagedCalendarEntity calendar;
  final bool isSelected;

  const ManagedCalendarVisibilityToggled({
    required this.userId,
    required this.calendar,
    required this.isSelected,
  });

  @override
  List<Object?> get props => [userId, calendar, isSelected];
}

final class ManagedCalendarsBulkVisibilitySet extends CalendarEvent {
  final String userId;
  final bool isSelected;
  final bool includeSystemFeeds;

  const ManagedCalendarsBulkVisibilitySet({
    required this.userId,
    required this.isSelected,
    this.includeSystemFeeds = false,
  });

  @override
  List<Object?> get props => [userId, isSelected, includeSystemFeeds];
}

final class ManagedCalendarDeleteSubmitted extends CalendarEvent {
  final String userId;
  final ManagedCalendarEntity calendar;

  const ManagedCalendarDeleteSubmitted({
    required this.userId,
    required this.calendar,
  });

  @override
  List<Object?> get props => [userId, calendar];
}

final class CalendarEventCreated extends CalendarEvent {
  final CreateCalendarEventParams params;
  const CalendarEventCreated(this.params);

  @override
  List<Object?> get props => [params];
}

final class CalendarEventUpdated extends CalendarEvent {
  final UpdateCalendarEventParams params;
  const CalendarEventUpdated(this.params);

  @override
  List<Object?> get props => [params];
}

final class CalendarEventDeleted extends CalendarEvent {
  final String userId;
  final String? familyId;
  final CalendarEventVisibility visibility;
  final String eventId;
  final String? googleCalendarId;
  final String? googleEventId;

  const CalendarEventDeleted({
    required this.userId,
    this.familyId,
    required this.visibility,
    required this.eventId,
    this.googleCalendarId,
    this.googleEventId,
  });

  @override
  List<Object?> get props => [
    userId,
    familyId,
    visibility,
    eventId,
    googleCalendarId,
    googleEventId,
  ];
}

final class GoogleCalendarSyncRequested extends CalendarEvent {
  final String userId;
  final String userName;
  final bool interactive;
  final String? manualAccessTokenOverride;

  const GoogleCalendarSyncRequested({
    required this.userId,
    required this.userName,
    this.interactive = true,
    this.manualAccessTokenOverride,
  });

  @override
  List<Object?> get props => [
    userId,
    userName,
    interactive,
    manualAccessTokenOverride,
  ];
}

final class CalendarState extends Equatable {
  final bool isLoading;
  final bool isSyncingGoogle;
  final bool isGoogleAuthorized;
  final List<ManagedCalendarEntity>? _calendarsInternal;
  final List<CalendarEventEntity> events;
  final String? selectedCalendarId;
  final String searchQuery;
  final GoogleCalendarSyncReport? lastSyncReport;
  final Failure? failure;
  final String? message;

  List<ManagedCalendarEntity> get calendars =>
      _calendarsInternal ?? const <ManagedCalendarEntity>[];

  const CalendarState({
    this.isLoading = false,
    this.isSyncingGoogle = false,
    this.isGoogleAuthorized = false,
    List<ManagedCalendarEntity> calendars = const [],
    this.events = const [],
    this.selectedCalendarId,
    this.searchQuery = '',
    this.lastSyncReport,
    this.failure,
    this.message,
  }) : _calendarsInternal = calendars;

  List<DeduplicatedCalendarGroup> get deduplicatedCalendars =>
      CalendarListDeduplicator.group(calendars);

  bool get hasHiddenUserCalendars =>
      deduplicatedCalendars.any((g) => !g.isSystemFeed && !g.isSelected);

  bool get hasActiveFilters =>
      (selectedCalendarId != null && selectedCalendarId!.isNotEmpty) ||
      searchQuery.trim().isNotEmpty ||
      hasHiddenUserCalendars;

  List<CalendarEventEntity> get filteredEvents {
    final groups = deduplicatedCalendars;
    final activeCalIds = <String>{
      for (final g in groups)
        if (g.isSelected) ...g.memberIds,
    };
    final selectedGroup =
        (selectedCalendarId != null &&
            selectedCalendarId!.isNotEmpty &&
            selectedCalendarId != '__family__')
        ? groups
              .where(
                (g) =>
                    g.canonicalId == selectedCalendarId ||
                    g.matchesCalendarId(selectedCalendarId),
              )
              .firstOrNull
        : null;
    final q = searchQuery.trim();

    final matched = events.where((ev) {
      if (selectedCalendarId != null && selectedCalendarId!.isNotEmpty) {
        if (selectedCalendarId == '__family__') {
          if (ev.visibility != CalendarEventVisibility.sharedEvent) {
            return false;
          }
        } else {
          if (ev.visibility != CalendarEventVisibility.privateEvent) {
            return false;
          }
          final matchesSelected = selectedGroup != null
              ? selectedGroup.matchesCalendarId(ev.calendarId)
              : ev.calendarId == selectedCalendarId;
          if (!matchesSelected) return false;
        }
      } else if (ev.visibility == CalendarEventVisibility.privateEvent &&
          calendars.isNotEmpty &&
          !activeCalIds.contains(ev.calendarId) &&
          ev.calendarId != 'primary') {
        return false;
      }

      if (q.isNotEmpty) {
        final matchesText = VietnameseSearchMatcher.matchesAny(q, [
          ev.title,
          ev.location,
          ev.description,
        ]);
        if (!matchesText) return false;
      }
      return true;
    }).toList();

    return CalendarListDeduplicator.deduplicateEvents(matched);
  }

  CalendarState copyWith({
    bool? isLoading,
    bool? isSyncingGoogle,
    bool? isGoogleAuthorized,
    List<ManagedCalendarEntity>? calendars,
    List<CalendarEventEntity>? events,
    String? selectedCalendarId,
    bool clearSelectedCalendar = false,
    String? searchQuery,
    GoogleCalendarSyncReport? lastSyncReport,
    Failure? failure,
    bool clearFailure = false,
    String? message,
    bool clearMessage = false,
  }) {
    return CalendarState(
      isLoading: isLoading ?? this.isLoading,
      isSyncingGoogle: isSyncingGoogle ?? this.isSyncingGoogle,
      isGoogleAuthorized: isGoogleAuthorized ?? this.isGoogleAuthorized,
      calendars: calendars != null ? List.unmodifiable(calendars) : this.calendars,
      events: events != null ? List.unmodifiable(events) : this.events,
      selectedCalendarId: clearSelectedCalendar
          ? null
          : (selectedCalendarId ?? this.selectedCalendarId),
      searchQuery: searchQuery ?? this.searchQuery,
      lastSyncReport: lastSyncReport ?? this.lastSyncReport,
      failure: clearFailure ? null : (failure ?? this.failure),
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    isSyncingGoogle,
    isGoogleAuthorized,
    calendars,
    events,
    selectedCalendarId,
    searchQuery,
    lastSyncReport,
    failure,
    message,
  ];
}

class CalendarBloc extends Bloc<CalendarEvent, CalendarState> {
  final CalendarRepository _repository;
  final CreateManagedCalendarUseCase _createCalendar;
  final CreateCalendarEventUseCase _createEvent;
  final UpdateCalendarEventUseCase _updateEvent;
  final SyncGoogleCalendarUseCase _syncGoogle;

  CalendarBloc({
    required CalendarRepository repository,
    CreateManagedCalendarUseCase? createCalendar,
    required CreateCalendarEventUseCase createEvent,
    UpdateCalendarEventUseCase? updateEvent,
    SyncGoogleCalendarUseCase? syncGoogle,
  }) : _repository = repository,
       _createCalendar =
           createCalendar ?? CreateManagedCalendarUseCase(repository),
       _createEvent = createEvent,
       _updateEvent = updateEvent ?? UpdateCalendarEventUseCase(repository),
       _syncGoogle = syncGoogle ?? SyncGoogleCalendarUseCase(repository),
       super(
         CalendarState(
           isGoogleAuthorized: repository.isGoogleCalendarAuthorized,
         ),
       ) {
    on<CalendarWatchStarted>(_onWatchStarted, transformer: restartable());
    on<CalendarFilterSelected>(_onFilterSelected);
    on<CalendarSearchChanged>(_onSearchChanged);
    on<CalendarFiltersReset>(_onFiltersReset, transformer: sequential());
    on<ManagedCalendarCreateSubmitted>(
      _onManagedCalendarCreated,
      transformer: sequential(),
    );
    on<ManagedCalendarVisibilityToggled>(
      _onManagedCalendarToggled,
      transformer: sequential(),
    );
    on<ManagedCalendarsBulkVisibilitySet>(
      _onManagedCalendarsBulkVisibilitySet,
      transformer: sequential(),
    );
    on<ManagedCalendarDeleteSubmitted>(
      _onManagedCalendarDeleted,
      transformer: sequential(),
    );
    on<CalendarEventCreated>(_onEventCreated, transformer: sequential());
    on<CalendarEventUpdated>(_onEventUpdated, transformer: sequential());
    on<CalendarEventDeleted>(_onEventDeleted, transformer: sequential());
    on<GoogleCalendarSyncRequested>(
      _onGoogleSyncRequested,
      transformer: droppable(),
    );
  }

  Future<void> _onWatchStarted(
    CalendarWatchStarted event,
    Emitter<CalendarState> emit,
  ) async {
    final orphanFamilyFilter =
        (event.familyId == null || event.familyId!.isEmpty) &&
        state.selectedCalendarId == '__family__';
    emit(
      state.copyWith(
        isLoading: true,
        isGoogleAuthorized: _repository.isGoogleCalendarAuthorized,
        clearSelectedCalendar: orphanFamilyFilter,
        clearFailure: true,
        clearMessage: true,
      ),
    );

    final combinedStream = StreamCombiner.combine2(
      _repository.watchCalendars(event.userId),
      _repository.watchEvents(userId: event.userId, familyId: event.familyId),
      (calRes, evRes) => (calRes: calRes, evRes: evRes),
    );

    await emit.forEach(
      combinedStream,
      onData: (pair) {
        Failure? err;
        var nextCalendars = state.calendars;
        var nextEvents = state.events;

        pair.calRes.fold((f) => err = f, (cals) => nextCalendars = cals);
        pair.evRes.fold((f) => err = f, (evs) => nextEvents = evs);

        return state.copyWith(
          isLoading: false,
          isGoogleAuthorized: _repository.isGoogleCalendarAuthorized,
          calendars: nextCalendars,
          events: nextEvents,
          failure: err,
          clearFailure: err == null,
          clearMessage: true,
        );
      },
    );
  }

  void _onFilterSelected(
    CalendarFilterSelected event,
    Emitter<CalendarState> emit,
  ) {
    if (event.calendarId == null ||
        event.calendarId!.isEmpty ||
        event.calendarId == state.selectedCalendarId) {
      emit(state.copyWith(clearSelectedCalendar: true));
    } else {
      emit(state.copyWith(selectedCalendarId: event.calendarId));
    }
  }

  void _onSearchChanged(
    CalendarSearchChanged event,
    Emitter<CalendarState> emit,
  ) {
    emit(state.copyWith(searchQuery: event.query));
  }

  Future<void> _onFiltersReset(
    CalendarFiltersReset event,
    Emitter<CalendarState> emit,
  ) async {
    emit(
      state.copyWith(
        clearSelectedCalendar: true,
        searchQuery: '',
        clearFailure: true,
        clearMessage: true,
      ),
    );
    final uid = event.userId;
    if (uid != null && uid.isNotEmpty && event.enableHiddenUserCalendars) {
      final groups = state.deduplicatedCalendars.where(
        (g) => !g.isSystemFeed && !g.isSelected,
      );
      for (final g in groups) {
        for (final member in g.members) {
          await _repository.updateCalendar(
            userId: uid,
            calendar: member.copyWith(isSelected: true),
          );
        }
      }
    }
  }

  Future<void> _onManagedCalendarCreated(
    ManagedCalendarCreateSubmitted event,
    Emitter<CalendarState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true, clearMessage: true));
    final res = await _createCalendar(event.params);
    res.fold(
      (f) => emit(state.copyWith(failure: f, clearMessage: true)),
      (cal) => emit(
        state.copyWith(
          isGoogleAuthorized: _repository.isGoogleCalendarAuthorized,
          message: cal.isGoogleSynced
              ? 'Đã tạo bộ lịch "${cal.summary}" trực tiếp trên Google Calendar!'
              : 'Đã tạo bộ lịch mới "${cal.summary}".',
        ),
      ),
    );
  }

  Future<void> _onManagedCalendarToggled(
    ManagedCalendarVisibilityToggled event,
    Emitter<CalendarState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true, clearMessage: true));
    final matchingGroup = state.deduplicatedCalendars
        .where((g) => g.matchesCalendarId(event.calendar.id))
        .firstOrNull;
    final targets =
        matchingGroup?.members ?? <ManagedCalendarEntity>[event.calendar];

    Failure? firstFailure;
    for (final target in targets) {
      final res = await _repository.updateCalendar(
        userId: event.userId,
        calendar: target.copyWith(isSelected: event.isSelected),
      );
      res.fold((f) => firstFailure ??= f, (_) {});
    }
    if (firstFailure != null) {
      emit(state.copyWith(failure: firstFailure, clearMessage: true));
    }
  }

  Future<void> _onManagedCalendarsBulkVisibilitySet(
    ManagedCalendarsBulkVisibilitySet event,
    Emitter<CalendarState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true, clearMessage: true));
    final groups = state.deduplicatedCalendars.where(
      (g) => event.includeSystemFeeds || !g.isSystemFeed,
    );
    Failure? firstFailure;
    for (final g in groups) {
      for (final member in g.members) {
        if (!event.isSelected && (member.isPrimary || member.id == 'primary')) {
          continue;
        }
        if (member.isSelected == event.isSelected) continue;
        final res = await _repository.updateCalendar(
          userId: event.userId,
          calendar: member.copyWith(isSelected: event.isSelected),
        );
        res.fold((f) => firstFailure ??= f, (_) {});
      }
    }
    if (firstFailure != null) {
      emit(state.copyWith(failure: firstFailure, clearMessage: true));
    } else {
      emit(
        state.copyWith(
          message: event.isSelected
              ? 'Đã bật hiển thị tất cả bộ lịch.'
              : 'Đã ẩn bớt các bộ lịch phụ.',
        ),
      );
    }
  }

  Future<void> _onManagedCalendarDeleted(
    ManagedCalendarDeleteSubmitted event,
    Emitter<CalendarState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true, clearMessage: true));
    final matchingGroup = state.deduplicatedCalendars
        .where((g) => g.matchesCalendarId(event.calendar.id))
        .firstOrNull;
    final targets =
        (matchingGroup?.members ?? <ManagedCalendarEntity>[event.calendar])
            .where((m) => !m.isPrimary && m.id != 'primary')
            .toList();
    if (targets.isEmpty) {
      final res = await _repository.deleteCalendar(
        userId: event.userId,
        calendar: event.calendar,
      );
      res.fold(
        (f) => emit(state.copyWith(failure: f, clearMessage: true)),
        (_) => emit(
          state.copyWith(
            clearSelectedCalendar: state.selectedCalendarId == event.calendar.id,
            message: 'Đã xóa bộ lịch "${event.calendar.summary}".',
          ),
        ),
      );
      return;
    }

    Failure? firstFailure;
    for (final target in targets) {
      final res = await _repository.deleteCalendar(
        userId: event.userId,
        calendar: target,
      );
      res.fold((f) => firstFailure ??= f, (_) {});
    }
    if (firstFailure != null) {
      emit(state.copyWith(failure: firstFailure, clearMessage: true));
    } else {
      final shouldClearFilter = matchingGroup != null
          ? matchingGroup.matchesCalendarId(state.selectedCalendarId)
          : state.selectedCalendarId == event.calendar.id;
      emit(
        state.copyWith(
          clearSelectedCalendar: shouldClearFilter,
          message:
              'Đã xóa bộ lịch "${matchingGroup?.displayTitle ?? event.calendar.summary}".',
        ),
      );
    }
  }

  Future<void> _syncEventReminderAlarm(CalendarEventEntity ev) async {
    if (ev.isAllDay || ev.reminderMinutesBefore <= 0) {
      return;
    }
    final now = DateTime.now();
    if (!ev.startsAt.isAfter(now.add(const Duration(seconds: 30)))) {
      return;
    }
    await NativeAlarmSchedulerBridge.instance.scheduleEventAlarm(
      eventId: ev.id,
      title: ev.title,
      subtitle: (ev.location ?? '').trim().isNotEmpty
          ? ev.location!.trim()
          : 'Lịch hẹn sắp diễn ra',
      eventStartsAt: ev.startsAt,
      minutesBefore: ev.reminderMinutesBefore,
      fullScreen: false,
    );
  }

  Future<void> _onEventCreated(
    CalendarEventCreated event,
    Emitter<CalendarState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true, clearMessage: true));
    final res = await _createEvent(event.params);
    CalendarEventEntity? created;
    res.fold(
      (f) => emit(state.copyWith(failure: f, clearMessage: true)),
      (ev) {
        created = ev;
        emit(
          state.copyWith(
            isGoogleAuthorized: _repository.isGoogleCalendarAuthorized,
            message: ev.syncStatus == CalendarSyncStatus.synced
                ? 'Đã lưu & đồng bộ sự kiện vào Lịch!'
                : ev.visibility == CalendarEventVisibility.privateEvent
                ? 'Đã lưu sự kiện riêng tư${ev.isRecurring ? " (${ev.recurrence.humanReadableVi})" : ""}.'
                : 'Đã chia sẻ sự kiện lên lịch gia đình.',
          ),
        );
      },
    );
    if (created != null) {
      await _syncEventReminderAlarm(created!);
    }
  }

  Future<void> _onEventUpdated(
    CalendarEventUpdated event,
    Emitter<CalendarState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true, clearMessage: true));
    final res = await _updateEvent(event.params);
    CalendarEventEntity? updated;
    res.fold(
      (f) => emit(state.copyWith(failure: f, clearMessage: true)),
      (ev) {
        updated = ev;
        emit(
          state.copyWith(
            isGoogleAuthorized: _repository.isGoogleCalendarAuthorized,
            message: ev.syncStatus == CalendarSyncStatus.synced
                ? 'Đã cập nhật & đồng bộ sự kiện vào Lịch!'
                : 'Đã cập nhật sự kiện "${ev.title}".',
          ),
        );
      },
    );
    if (updated != null) {
      if (updated!.reminderMinutesBefore <= 0) {
        await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(updated!.id);
      } else {
        await _syncEventReminderAlarm(updated!);
      }
    }
  }

  Future<void> _onEventDeleted(
    CalendarEventDeleted event,
    Emitter<CalendarState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true, clearMessage: true));
    final res = await _repository.deleteEvent(
      userId: event.userId,
      familyId: event.familyId,
      visibility: event.visibility,
      eventId: event.eventId,
      googleCalendarId: event.googleCalendarId,
      googleEventId: event.googleEventId,
    );
    var deletedOk = false;
    res.fold(
      (f) => emit(state.copyWith(failure: f, clearMessage: true)),
      (_) {
        deletedOk = true;
        emit(state.copyWith(message: 'Đã xóa sự kiện khỏi lịch.'));
      },
    );
    if (deletedOk) {
      await NativeAlarmSchedulerBridge.instance.cancelEventAlarm(event.eventId);
    }
  }

  Future<void> _onGoogleSyncRequested(
    GoogleCalendarSyncRequested event,
    Emitter<CalendarState> emit,
  ) async {
    emit(
      state.copyWith(
        isSyncingGoogle: true,
        clearFailure: true,
        clearMessage: true,
      ),
    );
    final res = await _syncGoogle(
      SyncGoogleCalendarParams(
        userId: event.userId,
        userName: event.userName,
        interactivePromptIfNeeded: event.interactive,
        manualAccessTokenOverride: event.manualAccessTokenOverride,
      ),
    );
    res.fold(
      (f) => emit(
        state.copyWith(
          isSyncingGoogle: false,
          isGoogleAuthorized: _repository.isGoogleCalendarAuthorized,
          failure: event.interactive ? f : null,
          clearFailure: !event.interactive,
          clearMessage: true,
        ),
      ),
      (report) => emit(
        state.copyWith(
          isSyncingGoogle: false,
          isGoogleAuthorized: true,
          lastSyncReport: report,
          message: event.interactive ? report.summaryVi : null,
          clearMessage: !event.interactive,
        ),
      ),
    );
  }
}
