import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/daily_life_entities.dart';
import '../../domain/repositories/daily_life_repository.dart';

sealed class DailyLifeEvent extends Equatable {
  const DailyLifeEvent();

  @override
  List<Object?> get props => [];
}

final class DailyLifeWatchStarted extends DailyLifeEvent {
  final String userId;
  const DailyLifeWatchStarted(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class MedicationCabinetAdded extends DailyLifeEvent {
  final String userId;
  final String name;
  final String dosage;
  final MedicationScheduleSlot slot;
  final int remainingPills;
  final DateTime expiryDate;
  final String memberName;

  const MedicationCabinetAdded({
    required this.userId,
    required this.name,
    required this.dosage,
    required this.slot,
    required this.remainingPills,
    required this.expiryDate,
    this.memberName = 'Cả gia đình',
  });

  @override
  List<Object?> get props => [
    userId,
    name,
    dosage,
    slot,
    remainingPills,
    expiryDate,
    memberName,
  ];
}

final class MedicationTakenToggled extends DailyLifeEvent {
  final String userId;
  final MedicationCabinetItemEntity item;

  const MedicationTakenToggled({required this.userId, required this.item});

  @override
  List<Object?> get props => [userId, item];
}

final class MedicationCabinetDeleted extends DailyLifeEvent {
  final String userId;
  final String medId;

  const MedicationCabinetDeleted({required this.userId, required this.medId});

  @override
  List<Object?> get props => [userId, medId];
}

final class HealthVitalLogAdded extends DailyLifeEvent {
  final String userId;
  final double weightKg;
  final double heightCm;
  final int systolicMmHg;
  final int diastolicMmHg;
  final int heartRateBpm;
  final double sleepHours;
  final String note;

  const HealthVitalLogAdded({
    required this.userId,
    required this.weightKg,
    required this.heightCm,
    required this.systolicMmHg,
    required this.diastolicMmHg,
    required this.heartRateBpm,
    required this.sleepHours,
    this.note = '',
  });

  @override
  List<Object?> get props => [
    userId,
    weightKg,
    heightCm,
    systolicMmHg,
    diastolicMmHg,
    heartRateBpm,
    sleepHours,
    note,
  ];
}

final class EmergencyMedicalCardSaved extends DailyLifeEvent {
  final EmergencyMedicalCardEntity card;
  const EmergencyMedicalCardSaved(this.card);

  @override
  List<Object?> get props => [card];
}

final class GroceryItemAdded extends DailyLifeEvent {
  final String userId;
  final String name;
  final String quantityLabel;
  final GroceryAisle aisle;
  final int estimatedMinor;
  final bool inFridgeStorage;
  final DateTime? expiryDate;

  const GroceryItemAdded({
    required this.userId,
    required this.name,
    required this.quantityLabel,
    required this.aisle,
    required this.estimatedMinor,
    this.inFridgeStorage = false,
    this.expiryDate,
  });

  @override
  List<Object?> get props => [
    userId,
    name,
    quantityLabel,
    aisle,
    estimatedMinor,
    inFridgeStorage,
    expiryDate,
  ];
}

final class MealComboAppliedToGroceries extends DailyLifeEvent {
  final String userId;
  final MealComboPreset combo;

  const MealComboAppliedToGroceries({
    required this.userId,
    required this.combo,
  });

  @override
  List<Object?> get props => [userId, combo];
}

final class GroceryItemBoughtToggled extends DailyLifeEvent {
  final String userId;
  final SmartGroceryItemEntity item;

  const GroceryItemBoughtToggled({required this.userId, required this.item});

  @override
  List<Object?> get props => [userId, item];
}

final class BoughtGroceriesCleared extends DailyLifeEvent {
  final String userId;
  const BoughtGroceriesCleared(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class GroceryItemDeleted extends DailyLifeEvent {
  final String userId;
  final String itemId;

  const GroceryItemDeleted({required this.userId, required this.itemId});

  @override
  List<Object?> get props => [userId, itemId];
}

final class UtilityReadingSaved extends DailyLifeEvent {
  final String userId;
  final String monthKey;
  final int prevElectricKwh;
  final int currElectricKwh;
  final int prevWaterM3;
  final int currWaterM3;
  final bool useEvnTieredTariff;
  final int fixedServicesMinor;
  final int totalAmountMinor;

  const UtilityReadingSaved({
    required this.userId,
    required this.monthKey,
    required this.prevElectricKwh,
    required this.currElectricKwh,
    required this.prevWaterM3,
    required this.currWaterM3,
    required this.useEvnTieredTariff,
    required this.fixedServicesMinor,
    required this.totalAmountMinor,
  });

  @override
  List<Object?> get props => [
    userId,
    monthKey,
    prevElectricKwh,
    currElectricKwh,
    prevWaterM3,
    currWaterM3,
    useEvnTieredTariff,
    fixedServicesMinor,
    totalAmountMinor,
  ];
}

final class UtilityReadingMarkedPaid extends DailyLifeEvent {
  final String userId;
  final String readingId;

  const UtilityReadingMarkedPaid({
    required this.userId,
    required this.readingId,
  });

  @override
  List<Object?> get props => [userId, readingId];
}

final class HomeContractSaved extends DailyLifeEvent {
  final String userId;
  final String homeName;
  final int monthlyRentMinor;
  final int depositMinor;
  final int paymentDayOfMonth;
  final DateTime leaseEndDate;
  final String wifiCredentials;
  final String nextApplianceMaintenanceNote;

  const HomeContractSaved({
    required this.userId,
    required this.homeName,
    required this.monthlyRentMinor,
    required this.depositMinor,
    required this.paymentDayOfMonth,
    required this.leaseEndDate,
    required this.wifiCredentials,
    required this.nextApplianceMaintenanceNote,
  });

  @override
  List<Object?> get props => [
    userId,
    homeName,
    monthlyRentMinor,
    depositMinor,
    paymentDayOfMonth,
    leaseEndDate,
    wifiCredentials,
    nextApplianceMaintenanceNote,
  ];
}

final class SmartNoteSaved extends DailyLifeEvent {
  final String userId;
  final String? existingId;
  final String title;
  final String content;
  final String categoryTag;
  final LifeMoodLevel? mood;
  final bool isPinned;

  const SmartNoteSaved({
    required this.userId,
    this.existingId,
    required this.title,
    required this.content,
    required this.categoryTag,
    this.mood,
    this.isPinned = false,
  });

  @override
  List<Object?> get props => [
    userId,
    existingId,
    title,
    content,
    categoryTag,
    mood,
    isPinned,
  ];
}

final class SmartNotePinToggled extends DailyLifeEvent {
  final String userId;
  final SmartLifeNoteEntity note;

  const SmartNotePinToggled({required this.userId, required this.note});

  @override
  List<Object?> get props => [userId, note];
}

final class SmartNoteDeleted extends DailyLifeEvent {
  final String userId;
  final String noteId;

  const SmartNoteDeleted({required this.userId, required this.noteId});

  @override
  List<Object?> get props => [userId, noteId];
}

class DailyLifeState extends Equatable {
  final bool isLoading;
  final DailyLifeSnapshot snapshot;
  final Failure? failure;
  final String? successBanner;

  const DailyLifeState({
    this.isLoading = true,
    this.snapshot = DailyLifeSnapshot.empty,
    this.failure,
    this.successBanner,
  });

  DailyLifeState copyWith({
    bool? isLoading,
    DailyLifeSnapshot? snapshot,
    Failure? failure,
    bool clearFailure = false,
    String? successBanner,
    bool clearSuccess = false,
  }) {
    return DailyLifeState(
      isLoading: isLoading ?? this.isLoading,
      snapshot: snapshot ?? this.snapshot,
      failure: clearFailure ? null : (failure ?? this.failure),
      successBanner: clearSuccess
          ? null
          : (successBanner ?? this.successBanner),
    );
  }

  @override
  List<Object?> get props => [isLoading, snapshot, failure, successBanner];
}

class DailyLifeBloc extends Bloc<DailyLifeEvent, DailyLifeState> {
  final DailyLifeRepository _repository;

  DailyLifeBloc(this._repository) : super(const DailyLifeState()) {
    on<DailyLifeWatchStarted>(_onWatchStarted, transformer: restartable());
    on<MedicationCabinetAdded>(_onMedAdded, transformer: sequential());
    on<MedicationTakenToggled>(_onMedToggled, transformer: sequential());
    on<MedicationCabinetDeleted>(_onMedDeleted, transformer: sequential());
    on<HealthVitalLogAdded>(_onVitalAdded, transformer: sequential());
    on<EmergencyMedicalCardSaved>(
      _onEmergencyCardSaved,
      transformer: sequential(),
    );
    on<GroceryItemAdded>(_onGroceryAdded, transformer: sequential());
    on<MealComboAppliedToGroceries>(
      _onMealComboApplied,
      transformer: sequential(),
    );
    on<GroceryItemBoughtToggled>(
      _onGroceryBoughtToggled,
      transformer: sequential(),
    );
    on<BoughtGroceriesCleared>(
      _onBoughtGroceriesCleared,
      transformer: sequential(),
    );
    on<GroceryItemDeleted>(_onGroceryDeleted, transformer: sequential());
    on<UtilityReadingSaved>(_onUtilityReadingSaved, transformer: sequential());
    on<UtilityReadingMarkedPaid>(
      _onUtilityMarkedPaid,
      transformer: sequential(),
    );
    on<HomeContractSaved>(_onHomeContractSaved, transformer: sequential());
    on<SmartNoteSaved>(_onNoteSaved, transformer: sequential());
    on<SmartNotePinToggled>(_onNotePinToggled, transformer: sequential());
    on<SmartNoteDeleted>(_onNoteDeleted, transformer: sequential());
  }

  static String todayDayKey() =>
      DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _onWatchStarted(
    DailyLifeWatchStarted event,
    Emitter<DailyLifeState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));
    await emit.forEach<DailyLifeSnapshot>(
      _repository.watchAll(userId: event.userId),
      onData: (data) =>
          state.copyWith(isLoading: false, snapshot: data, clearFailure: true),
      onError: (err, _) => state.copyWith(
        isLoading: false,
        failure: UnexpectedFailure(message: err.toString()),
      ),
    );
  }

  Future<void> _onMedAdded(
    MedicationCabinetAdded e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.addMedication(
      userId: e.userId,
      name: e.name,
      dosage: e.dosage,
      slot: e.slot,
      remainingPills: e.remainingPills,
      expiryDate: e.expiryDate,
      memberName: e.memberName,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          clearFailure: true,
          successBanner: '✓ Đã thêm "${e.name}" vào Tủ thuốc & Lịch nhắc.',
        ),
      ),
    );
  }

  Future<void> _onMedToggled(
    MedicationTakenToggled e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.toggleMedicationToday(
      userId: e.userId,
      item: e.item,
      dayKey: todayDayKey(),
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(clearFailure: true)),
    );
  }

  Future<void> _onMedDeleted(
    MedicationCabinetDeleted e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.deleteMedication(
      userId: e.userId,
      medId: e.medId,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(clearFailure: true)),
    );
  }

  Future<void> _onVitalAdded(
    HealthVitalLogAdded e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.addHealthVitalLog(
      userId: e.userId,
      weightKg: e.weightKg,
      heightCm: e.heightCm,
      systolicMmHg: e.systolicMmHg,
      diastolicMmHg: e.diastolicMmHg,
      heartRateBpm: e.heartRateBpm,
      sleepHours: e.sleepHours,
      note: e.note,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          clearFailure: true,
          successBanner:
              '✓ Đã lưu chỉ số sức khỏe & cập nhật hồ sơ BMI/Huyết áp.',
        ),
      ),
    );
  }

  Future<void> _onEmergencyCardSaved(
    EmergencyMedicalCardSaved e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.saveEmergencyMedicalCard(card: e.card);
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          clearFailure: true,
          successBanner: '✓ Đã lưu Thẻ Y Tế Khẩn Cấp (ICE & BHYT).',
        ),
      ),
    );
  }

  Future<void> _onGroceryAdded(
    GroceryItemAdded e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.addGroceryItem(
      userId: e.userId,
      name: e.name,
      quantityLabel: e.quantityLabel,
      aisle: e.aisle,
      estimatedMinor: e.estimatedMinor,
      inFridgeStorage: e.inFridgeStorage,
      expiryDate: e.expiryDate,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          clearFailure: true,
          successBanner: e.inFridgeStorage
              ? '✓ Đã cất "${e.name}" vào Tủ lạnh theo dõi hạn dùng.'
              : '✓ Đã thêm "${e.name}" vào Giỏ đi chợ.',
        ),
      ),
    );
  }

  Future<void> _onMealComboApplied(
    MealComboAppliedToGroceries e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.seedMealComboIngredients(
      userId: e.userId,
      combo: e.combo,
      dayKey: todayDayKey(),
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          clearFailure: true,
          successBanner:
              '✓ Đã áp dụng "${e.combo.title}" & đẩy ${e.combo.ingredients.length} nguyên liệu sang Giỏ đi chợ!',
        ),
      ),
    );
  }

  Future<void> _onGroceryBoughtToggled(
    GroceryItemBoughtToggled e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.toggleGroceryBought(
      userId: e.userId,
      item: e.item,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(clearFailure: true)),
    );
  }

  Future<void> _onBoughtGroceriesCleared(
    BoughtGroceriesCleared e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.clearBoughtGroceries(userId: e.userId);
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          clearFailure: true,
          successBanner: '✓ Đã chốt Giỏ chợ & dọn danh sách các món đã mua.',
        ),
      ),
    );
  }

  Future<void> _onGroceryDeleted(
    GroceryItemDeleted e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.deleteGroceryItem(
      userId: e.userId,
      itemId: e.itemId,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(clearFailure: true)),
    );
  }

  Future<void> _onUtilityReadingSaved(
    UtilityReadingSaved e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.saveUtilityReading(
      userId: e.userId,
      monthKey: e.monthKey,
      prevElectricKwh: e.prevElectricKwh,
      currElectricKwh: e.currElectricKwh,
      prevWaterM3: e.prevWaterM3,
      currWaterM3: e.currWaterM3,
      useEvnTieredTariff: e.useEvnTieredTariff,
      fixedServicesMinor: e.fixedServicesMinor,
      totalAmountMinor: e.totalAmountMinor,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          clearFailure: true,
          successBanner: '✓ Đã lưu sổ chỉ số Điện & Nước kỳ ${e.monthKey}.',
        ),
      ),
    );
  }

  Future<void> _onUtilityMarkedPaid(
    UtilityReadingMarkedPaid e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.markUtilityReadingPaid(
      userId: e.userId,
      readingId: e.readingId,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(clearFailure: true)),
    );
  }

  Future<void> _onHomeContractSaved(
    HomeContractSaved e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.saveHomeContract(
      userId: e.userId,
      homeName: e.homeName,
      monthlyRentMinor: e.monthlyRentMinor,
      depositMinor: e.depositMinor,
      paymentDayOfMonth: e.paymentDayOfMonth,
      leaseEndDate: e.leaseEndDate,
      wifiCredentials: e.wifiCredentials,
      nextApplianceMaintenanceNote: e.nextApplianceMaintenanceNote,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          clearFailure: true,
          successBanner: '✓ Đã lưu sổ Hợp đồng Nhà & Lịch bảo trì thiết bị.',
        ),
      ),
    );
  }

  Future<void> _onNoteSaved(
    SmartNoteSaved e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.addOrUpdateNote(
      userId: e.userId,
      existingId: e.existingId,
      title: e.title,
      content: e.content,
      categoryTag: e.categoryTag,
      mood: e.mood,
      isPinned: e.isPinned,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          clearFailure: true,
          successBanner: '✓ Đã lưu "${e.title}" vào Sổ tay LifeOS.',
        ),
      ),
    );
  }

  Future<void> _onNotePinToggled(
    SmartNotePinToggled e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.toggleNotePinned(
      userId: e.userId,
      note: e.note,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(clearFailure: true)),
    );
  }

  Future<void> _onNoteDeleted(
    SmartNoteDeleted e,
    Emitter<DailyLifeState> emit,
  ) async {
    final res = await _repository.deleteNote(
      userId: e.userId,
      noteId: e.noteId,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(clearFailure: true)),
    );
  }
}
