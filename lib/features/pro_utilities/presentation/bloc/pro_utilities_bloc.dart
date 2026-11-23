import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/pro_utilities_entities.dart';
import '../../domain/repositories/pro_utilities_repository.dart';

sealed class ProUtilitiesEvent extends Equatable {
  const ProUtilitiesEvent();

  @override
  List<Object?> get props => [];
}

final class ProUtilitiesWatchStarted extends ProUtilitiesEvent {
  final String userId;
  const ProUtilitiesWatchStarted(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class SubscriptionOrWarrantyAdded extends ProUtilitiesEvent {
  final String userId;
  final String title;
  final String providerOrStore;
  final SubscriptionCycle cycle;
  final int amountMinor;
  final DateTime nextBillingOrExpiryDate;
  final String serialOrNote;

  const SubscriptionOrWarrantyAdded({
    required this.userId,
    required this.title,
    required this.providerOrStore,
    required this.cycle,
    required this.amountMinor,
    required this.nextBillingOrExpiryDate,
    this.serialOrNote = '',
  });

  @override
  List<Object?> get props => [
    userId,
    title,
    providerOrStore,
    cycle,
    amountMinor,
    nextBillingOrExpiryDate,
    serialOrNote,
  ];
}

final class SubscriptionOrWarrantyDeleted extends ProUtilitiesEvent {
  final String userId;
  final String itemId;

  const SubscriptionOrWarrantyDeleted({
    required this.userId,
    required this.itemId,
  });

  @override
  List<Object?> get props => [userId, itemId];
}

final class HabitAdded extends ProUtilitiesEvent {
  final String userId;
  final String title;
  final String categoryTag;

  const HabitAdded({
    required this.userId,
    required this.title,
    required this.categoryTag,
  });

  @override
  List<Object?> get props => [userId, title, categoryTag];
}

final class HabitToggledToday extends ProUtilitiesEvent {
  final String userId;
  final LifeHabitEntity habit;

  const HabitToggledToday({required this.userId, required this.habit});

  @override
  List<Object?> get props => [userId, habit];
}

final class WellnessMetricsIncremented extends ProUtilitiesEvent {
  final String userId;
  final int addWaterMl;
  final int addFocusMinutes;
  final int addPomodoros;

  const WellnessMetricsIncremented({
    required this.userId,
    this.addWaterMl = 0,
    this.addFocusMinutes = 0,
    this.addPomodoros = 0,
  });

  @override
  List<Object?> get props => [
    userId,
    addWaterMl,
    addFocusMinutes,
    addPomodoros,
  ];
}

final class GiftLedgerEntrySubmitted extends ProUtilitiesEvent {
  final String userId;
  final String contactName;
  final String relationshipGroup;
  final GiftDirection direction;
  final GiftOccasion occasion;
  final int amountMinor;
  final String note;

  const GiftLedgerEntrySubmitted({
    required this.userId,
    required this.contactName,
    required this.relationshipGroup,
    required this.direction,
    required this.occasion,
    required this.amountMinor,
    this.note = '',
  });

  @override
  List<Object?> get props => [
    userId,
    contactName,
    relationshipGroup,
    direction,
    occasion,
    amountMinor,
    note,
  ];
}

final class PackingTemplateSeeded extends ProUtilitiesEvent {
  final String userId;
  final String tripName;
  final List<String> itemTitles;

  const PackingTemplateSeeded({
    required this.userId,
    required this.tripName,
    required this.itemTitles,
  });

  @override
  List<Object?> get props => [userId, tripName, itemTitles];
}

final class PackingItemToggled extends ProUtilitiesEvent {
  final String userId;
  final PackingChecklistItemEntity item;

  const PackingItemToggled({required this.userId, required this.item});

  @override
  List<Object?> get props => [userId, item];
}

final class ProUtilitiesState extends Equatable {
  final bool isLoading;
  final List<SubscriptionWarrantyEntity> subscriptionsAndWarranties;
  final List<LifeHabitEntity> habits;
  final DailyWellnessEntity todayWellness;
  final List<GiftLedgerEntryEntity> giftEntries;
  final List<PackingChecklistItemEntity> packingItems;
  final Failure? failure;
  final String? message;

  const ProUtilitiesState({
    this.isLoading = false,
    this.subscriptionsAndWarranties = const [],
    this.habits = const [],
    this.todayWellness = const DailyWellnessEntity(dateKey: ''),
    this.giftEntries = const [],
    this.packingItems = const [],
    this.failure,
    this.message,
  });

  List<SubscriptionWarrantyEntity> get subscriptionsOnly =>
      subscriptionsAndWarranties.where((e) => !e.isWarranty).toList();

  List<SubscriptionWarrantyEntity> get warrantiesOnly =>
      subscriptionsAndWarranties.where((e) => e.isWarranty).toList();

  int get totalMonthlySubBurnMinor =>
      subscriptionsOnly.fold<int>(0, (s, e) => s + e.monthlyEquivalentMinor);

  int get totalAnnualSubBurnMinor =>
      subscriptionsOnly.fold<int>(0, (s, e) => s + e.annualBurnMinor);

  int get totalGiftGaveMinor => giftEntries
      .where((g) => g.direction == GiftDirection.gave)
      .fold<int>(0, (s, g) => s + g.amountMinor);

  int get totalGiftReceivedMinor => giftEntries
      .where((g) => g.direction == GiftDirection.received)
      .fold<int>(0, (s, g) => s + g.amountMinor);

  ProUtilitiesState copyWith({
    bool? isLoading,
    List<SubscriptionWarrantyEntity>? subscriptionsAndWarranties,
    List<LifeHabitEntity>? habits,
    DailyWellnessEntity? todayWellness,
    List<GiftLedgerEntryEntity>? giftEntries,
    List<PackingChecklistItemEntity>? packingItems,
    Failure? failure,
    bool clearFailure = false,
    String? message,
    bool clearMessage = false,
  }) {
    return ProUtilitiesState(
      isLoading: isLoading ?? this.isLoading,
      subscriptionsAndWarranties:
          subscriptionsAndWarranties ?? this.subscriptionsAndWarranties,
      habits: habits ?? this.habits,
      todayWellness: todayWellness ?? this.todayWellness,
      giftEntries: giftEntries ?? this.giftEntries,
      packingItems: packingItems ?? this.packingItems,
      failure: clearFailure ? null : (failure ?? this.failure),
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    subscriptionsAndWarranties,
    habits,
    todayWellness,
    giftEntries,
    packingItems,
    failure,
    message,
  ];
}

class ProUtilitiesBloc extends Bloc<ProUtilitiesEvent, ProUtilitiesState> {
  final ProUtilitiesRepository _repository;

  ProUtilitiesBloc({required ProUtilitiesRepository repository})
    : _repository = repository,
      super(const ProUtilitiesState()) {
    on<ProUtilitiesWatchStarted>(_onWatchStarted, transformer: restartable());
    on<SubscriptionOrWarrantyAdded>(_onSubAdded, transformer: droppable());
    on<SubscriptionOrWarrantyDeleted>(_onSubDeleted, transformer: sequential());
    on<HabitAdded>(_onHabitAdded, transformer: droppable());
    on<HabitToggledToday>(_onHabitToggled, transformer: sequential());
    on<WellnessMetricsIncremented>(
      _onWellnessIncremented,
      transformer: sequential(),
    );
    on<GiftLedgerEntrySubmitted>(_onGiftSubmitted, transformer: droppable());
    on<PackingTemplateSeeded>(_onPackingSeeded, transformer: restartable());
    on<PackingItemToggled>(_onPackingToggled, transformer: sequential());
  }

  Future<void> _onWatchStarted(
    ProUtilitiesWatchStarted event,
    Emitter<ProUtilitiesState> emit,
  ) async {
    emit(
      state.copyWith(isLoading: true, clearFailure: true, clearMessage: true),
    );
    await emit.forEach<ProUtilitiesSnapshot>(
      _repository.watchAll(userId: event.userId),
      onData: (snap) => state.copyWith(
        isLoading: false,
        subscriptionsAndWarranties: snap.subscriptionsAndWarranties,
        habits: snap.habits,
        todayWellness: snap.todayWellness,
        giftEntries: snap.giftEntries,
        packingItems: snap.packingItems,
        clearFailure: true,
      ),
      onError: (err, _) => state.copyWith(
        isLoading: false,
        failure: UnexpectedFailure(message: 'Lỗi đồng bộ Tiện ích Pro: $err'),
      ),
    );
  }

  Future<void> _onSubAdded(
    SubscriptionOrWarrantyAdded event,
    Emitter<ProUtilitiesState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true, clearMessage: true));
    final res = await _repository.addSubscriptionOrWarranty(
      userId: event.userId,
      title: event.title,
      providerOrStore: event.providerOrStore,
      cycle: event.cycle,
      amountMinor: event.amountMinor,
      nextBillingOrExpiryDate: event.nextBillingOrExpiryDate,
      serialOrNote: event.serialOrNote,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(message: 'Đã lưu "${event.title}" vào Radar theo dõi.'),
      ),
    );
  }

  Future<void> _onSubDeleted(
    SubscriptionOrWarrantyDeleted event,
    Emitter<ProUtilitiesState> emit,
  ) async {
    final res = await _repository.deleteSubscriptionOrWarranty(
      userId: event.userId,
      itemId: event.itemId,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(message: 'Đã xóa mục khỏi danh sách.')),
    );
  }

  Future<void> _onHabitAdded(
    HabitAdded event,
    Emitter<ProUtilitiesState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true, clearMessage: true));
    final res = await _repository.addHabit(
      userId: event.userId,
      title: event.title,
      categoryTag: event.categoryTag,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) =>
          emit(state.copyWith(message: 'Đã thêm thói quen "${event.title}".')),
    );
  }

  Future<void> _onHabitToggled(
    HabitToggledToday event,
    Emitter<ProUtilitiesState> emit,
  ) async {
    final res = await _repository.toggleHabitToday(
      userId: event.userId,
      habit: event.habit,
      date: DateTime.now(),
    );
    res.fold((f) => emit(state.copyWith(failure: f)), (_) {});
  }

  Future<void> _onWellnessIncremented(
    WellnessMetricsIncremented event,
    Emitter<ProUtilitiesState> emit,
  ) async {
    final todayKey = LifeHabitEntity.formatDayKey(DateTime.now());
    final res = await _repository.updateDailyWellness(
      userId: event.userId,
      dateKey: todayKey,
      addWaterMl: event.addWaterMl,
      addFocusMinutes: event.addFocusMinutes,
      addPomodoros: event.addPomodoros,
    );
    res.fold((f) => emit(state.copyWith(failure: f)), (_) {});
  }

  Future<void> _onGiftSubmitted(
    GiftLedgerEntrySubmitted event,
    Emitter<ProUtilitiesState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true, clearMessage: true));
    final res = await _repository.addGiftEntry(
      userId: event.userId,
      contactName: event.contactName,
      relationshipGroup: event.relationshipGroup,
      direction: event.direction,
      occasion: event.occasion,
      amountMinor: event.amountMinor,
      note: event.note,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(message: 'Đã ghi sổ Hiếu Hỷ với ${event.contactName}.'),
      ),
    );
  }

  Future<void> _onPackingSeeded(
    PackingTemplateSeeded event,
    Emitter<ProUtilitiesState> emit,
  ) async {
    final res = await _repository.seedPackingTemplate(
      userId: event.userId,
      tripName: event.tripName,
      itemTitles: event.itemTitles,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(message: 'Đã nạp mẫu hành lý "${event.tripName}".'),
      ),
    );
  }

  Future<void> _onPackingToggled(
    PackingItemToggled event,
    Emitter<ProUtilitiesState> emit,
  ) async {
    final res = await _repository.togglePackingItem(
      userId: event.userId,
      item: event.item,
    );
    res.fold((f) => emit(state.copyWith(failure: f)), (_) {});
  }
}
