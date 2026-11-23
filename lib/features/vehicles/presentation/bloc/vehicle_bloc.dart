import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../domain/entities/vehicle_entities.dart';
import '../../domain/repositories/vehicle_repository.dart';

sealed class VehicleEvent extends Equatable {
  const VehicleEvent();

  @override
  List<Object?> get props => [];
}

final class VehiclesWatchStarted extends VehicleEvent {
  final String userId;
  final String? familyId;

  const VehiclesWatchStarted({required this.userId, this.familyId});

  @override
  List<Object?> get props => [userId, familyId];
}

final class VehicleCreated extends VehicleEvent {
  final String userId;
  final String? familyId;
  final bool isFamilyShared;
  final String name;
  final String plateNumber;
  final int currentOdometerKm;
  final int serviceIntervalKm;
  final int serviceIntervalDays;
  final VehicleCategory category;
  final String? modelProfileKey;
  final DateTime? insuranceExpiryDate;
  final DateTime? inspectionExpiryDate;

  const VehicleCreated({
    required this.userId,
    this.familyId,
    required this.isFamilyShared,
    required this.name,
    required this.plateNumber,
    required this.currentOdometerKm,
    this.serviceIntervalKm = 2000,
    this.serviceIntervalDays = 90,
    this.category = VehicleCategory.scooter,
    this.modelProfileKey,
    this.insuranceExpiryDate,
    this.inspectionExpiryDate,
  });

  @override
  List<Object?> get props => [
    userId,
    familyId,
    isFamilyShared,
    name,
    plateNumber,
    currentOdometerKm,
    serviceIntervalKm,
    serviceIntervalDays,
    category,
    modelProfileKey,
    insuranceExpiryDate,
    inspectionExpiryDate,
  ];
}

final class VehicleSpecProfileUpdated extends VehicleEvent {
  final VehicleEntity vehicle;
  final VehicleCategory category;
  final String modelProfileKey;
  final DateTime? insuranceExpiryDate;
  final DateTime? inspectionExpiryDate;

  const VehicleSpecProfileUpdated({
    required this.vehicle,
    required this.category,
    required this.modelProfileKey,
    this.insuranceExpiryDate,
    this.inspectionExpiryDate,
  });

  @override
  List<Object?> get props => [
    vehicle,
    category,
    modelProfileKey,
    insuranceExpiryDate,
    inspectionExpiryDate,
  ];
}

final class VehicleOdometerLogged extends VehicleEvent {
  final VehicleEntity vehicle;
  final int newOdometerKm;

  const VehicleOdometerLogged({
    required this.vehicle,
    required this.newOdometerKm,
  });

  @override
  List<Object?> get props => [vehicle, newOdometerKm];
}

final class VehicleMaintenanceLogged extends VehicleEvent {
  final VehicleEntity vehicle;
  final String serviceTitle;
  final int odometerKm;
  final int costMinor;
  final String? componentKey;
  final String? walletIdForExpense;

  const VehicleMaintenanceLogged({
    required this.vehicle,
    required this.serviceTitle,
    required this.odometerKm,
    required this.costMinor,
    this.componentKey,
    this.walletIdForExpense,
  });

  @override
  List<Object?> get props => [
    vehicle,
    serviceTitle,
    odometerKm,
    costMinor,
    componentKey,
    walletIdForExpense,
  ];
}

final class VehicleMaintenanceHistoryWatched extends VehicleEvent {
  final VehicleEntity vehicle;

  const VehicleMaintenanceHistoryWatched(this.vehicle);

  @override
  List<Object?> get props => [vehicle];
}

final class RecurringBillCreated extends VehicleEvent {
  final String userId;
  final String? familyId;
  final String title;
  final String providerName;
  final int estimatedAmountMinor;
  final DateTime nextDueDate;

  const RecurringBillCreated({
    required this.userId,
    this.familyId,
    required this.title,
    required this.providerName,
    required this.estimatedAmountMinor,
    required this.nextDueDate,
  });

  @override
  List<Object?> get props => [
    userId,
    familyId,
    title,
    providerName,
    estimatedAmountMinor,
    nextDueDate,
  ];
}

final class RecurringBillPaid extends VehicleEvent {
  final String userId;
  final RecurringBillEntity bill;
  final int paidAmountMinor;
  final String walletId;

  const RecurringBillPaid({
    required this.userId,
    required this.bill,
    required this.paidAmountMinor,
    required this.walletId,
  });

  @override
  List<Object?> get props => [userId, bill, paidAmountMinor, walletId];
}

final class VehicleState extends Equatable {
  final bool isLoading;
  final List<VehicleEntity> vehicles;
  final List<RecurringBillEntity> bills;
  final Map<String, List<MaintenanceRecordEntity>>
  maintenanceHistoryByVehicleId;
  final Failure? failure;
  final String? message;

  const VehicleState({
    this.isLoading = false,
    this.vehicles = const [],
    this.bills = const [],
    this.maintenanceHistoryByVehicleId = const {},
    this.failure,
    this.message,
  });

  VehicleState copyWith({
    bool? isLoading,
    List<VehicleEntity>? vehicles,
    List<RecurringBillEntity>? bills,
    Map<String, List<MaintenanceRecordEntity>>? maintenanceHistoryByVehicleId,
    Failure? failure,
    bool clearFailure = false,
    String? message,
    bool clearMessage = false,
  }) {
    return VehicleState(
      isLoading: isLoading ?? this.isLoading,
      vehicles: vehicles != null ? List.unmodifiable(vehicles) : this.vehicles,
      bills: bills != null ? List.unmodifiable(bills) : this.bills,
      maintenanceHistoryByVehicleId: maintenanceHistoryByVehicleId != null
          ? Map<String, List<MaintenanceRecordEntity>>.unmodifiable(
              maintenanceHistoryByVehicleId,
            )
          : this.maintenanceHistoryByVehicleId,
      failure: clearFailure ? null : (failure ?? this.failure),
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    vehicles,
    bills,
    maintenanceHistoryByVehicleId,
    failure,
    message,
  ];
}

class VehicleBloc extends Bloc<VehicleEvent, VehicleState> {
  final VehicleRepository _repository;
  final UpdateOdometerUseCase _updateOdometer;

  VehicleBloc({
    required VehicleRepository repository,
    required UpdateOdometerUseCase updateOdometer,
  }) : _repository = repository,
       _updateOdometer = updateOdometer,
       super(const VehicleState()) {
    on<VehiclesWatchStarted>(_onWatchStarted, transformer: restartable());
    on<VehicleMaintenanceHistoryWatched>(
      _onWatchMaintenanceHistory,
      transformer: restartable(),
    );
    on<VehicleCreated>(_onCreateVehicle, transformer: sequential());
    on<VehicleSpecProfileUpdated>(
      _onUpdateSpecProfile,
      transformer: sequential(),
    );
    on<VehicleOdometerLogged>(_onOdometerLogged, transformer: sequential());
    on<VehicleMaintenanceLogged>(
      _onMaintenanceLogged,
      transformer: sequential(),
    );
    on<RecurringBillCreated>(_onCreateBill, transformer: sequential());
    on<RecurringBillPaid>(_onPayBill, transformer: sequential());
  }

  Future<void> _onWatchMaintenanceHistory(
    VehicleMaintenanceHistoryWatched event,
    Emitter<VehicleState> emit,
  ) async {
    await emit.forEach<Result<List<MaintenanceRecordEntity>>>(
      _repository.watchMaintenanceHistory(vehicle: event.vehicle),
      onData: (res) => res.fold(
        (_) => state,
        (records) => state.copyWith(
          maintenanceHistoryByVehicleId: {
            ...state.maintenanceHistoryByVehicleId,
            event.vehicle.id: List.unmodifiable(records),
          },
        ),
      ),
    );
  }

  Future<void> _onWatchStarted(
    VehiclesWatchStarted event,
    Emitter<VehicleState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));
    final stream =
        StreamCombiner.combine2<
          Result<List<VehicleEntity>>,
          Result<List<RecurringBillEntity>>,
          VehicleState
        >(
          _repository.watchVehicles(
            userId: event.userId,
            familyId: event.familyId,
          ),
          _repository.watchRecurringBills(
            userId: event.userId,
            familyId: event.familyId,
          ),
          (vRes, bRes) {
            if (vRes is Err<List<VehicleEntity>>) {
              return state.copyWith(isLoading: false, failure: vRes.failure);
            }
            if (bRes is Err<List<RecurringBillEntity>>) {
              return state.copyWith(isLoading: false, failure: bRes.failure);
            }
            return state.copyWith(
              isLoading: false,
              vehicles: (vRes as Success<List<VehicleEntity>>).value,
              bills: (bRes as Success<List<RecurringBillEntity>>).value,
              clearFailure: true,
            );
          },
        );

    await emit.forEach<VehicleState>(stream, onData: (s) => s);
  }

  Future<void> _onCreateVehicle(
    VehicleCreated event,
    Emitter<VehicleState> emit,
  ) async {
    if (event.name.trim().length < 2 || event.plateNumber.trim().length < 4) {
      emit(
        state.copyWith(
          failure: const ValidationFailure(
            message: 'Vui lòng nhập tên xe và biển số hợp lệ.',
          ),
        ),
      );
      return;
    }
    final res = await _repository.createVehicle(
      userId: event.userId,
      familyId: event.familyId,
      isFamilyShared: event.isFamilyShared,
      name: event.name.trim(),
      plateNumber: event.plateNumber.trim().toUpperCase(),
      currentOdometerKm: event.currentOdometerKm < 0
          ? 0
          : event.currentOdometerKm,
      serviceIntervalKm: event.serviceIntervalKm,
      serviceIntervalDays: event.serviceIntervalDays,
      category: event.category,
      modelProfileKey: event.modelProfileKey,
      insuranceExpiryDate: event.insuranceExpiryDate,
      inspectionExpiryDate: event.inspectionExpiryDate,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          message: 'Đã thêm hồ sơ xe và lịch bảo dưỡng chuẩn hãng.',
        ),
      ),
    );
  }

  Future<void> _onUpdateSpecProfile(
    VehicleSpecProfileUpdated event,
    Emitter<VehicleState> emit,
  ) async {
    final res = await _repository.updateVehicleSpecProfile(
      vehicle: event.vehicle,
      category: event.category,
      modelProfileKey: event.modelProfileKey,
      insuranceExpiryDate: event.insuranceExpiryDate,
      inspectionExpiryDate: event.inspectionExpiryDate,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          message: 'Đã cập nhật dòng máy và thông số bảo dưỡng chuẩn hãng.',
        ),
      ),
    );
  }

  Future<void> _onOdometerLogged(
    VehicleOdometerLogged event,
    Emitter<VehicleState> emit,
  ) async {
    final res = await _updateOdometer(
      UpdateOdometerParams(
        vehicle: event.vehicle,
        newOdometerKm: event.newOdometerKm,
      ),
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(message: 'Đã cập nhật Odometer và tính lại hạn nhắc.'),
      ),
    );
  }

  Future<void> _onMaintenanceLogged(
    VehicleMaintenanceLogged event,
    Emitter<VehicleState> emit,
  ) async {
    final res = await _repository.recordMaintenance(
      vehicle: event.vehicle,
      serviceTitle: event.serviceTitle.trim().isEmpty
          ? 'Bảo dưỡng định kỳ'
          : event.serviceTitle.trim(),
      odometerKm: event.odometerKm,
      costMinor: event.costMinor < 0 ? 0 : event.costMinor,
      componentKey: event.componentKey,
      walletIdForExpense: event.walletIdForExpense,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(message: 'Đã lưu lịch sử bảo dưỡng xe.')),
    );
  }

  Future<void> _onCreateBill(
    RecurringBillCreated event,
    Emitter<VehicleState> emit,
  ) async {
    if (event.title.trim().length < 2 || event.estimatedAmountMinor <= 0) {
      emit(
        state.copyWith(
          failure: const ValidationFailure(
            message: 'Tên hóa đơn và số tiền dự kiến phải hợp lệ.',
          ),
        ),
      );
      return;
    }
    final res = await _repository.createRecurringBill(
      userId: event.userId,
      familyId: event.familyId,
      title: event.title.trim(),
      providerName: event.providerName.trim(),
      estimatedAmountMinor: event.estimatedAmountMinor,
      nextDueDate: event.nextDueDate,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(message: 'Đã thêm hóa đơn định kỳ.')),
    );
  }

  Future<void> _onPayBill(
    RecurringBillPaid event,
    Emitter<VehicleState> emit,
  ) async {
    if (event.paidAmountMinor <= 0) {
      emit(
        state.copyWith(
          failure: const ValidationFailure(
            message: 'Số tiền thanh toán phải lớn hơn 0 ₫.',
          ),
        ),
      );
      return;
    }
    final res = await _repository.payRecurringBill(
      userId: event.userId,
      bill: event.bill,
      paidAmountMinor: event.paidAmountMinor,
      walletId: event.walletId,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (spike) => emit(
        state.copyWith(
          message: spike
              ? '⚠ Đã thanh toán hóa đơn — Cảnh báo: kỳ này cao hơn >= 25% mức trung bình!'
              : 'Đã thanh toán hóa đơn và đẩy kỳ hạn sang tháng tới.',
        ),
      ),
    );
  }
}
