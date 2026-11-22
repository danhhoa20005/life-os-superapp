import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/vehicle_entities.dart';

abstract interface class VehicleRepository {
  Stream<Result<List<VehicleEntity>>> watchVehicles({
    required String userId,
    String? familyId,
  });

  Stream<Result<List<RecurringBillEntity>>> watchRecurringBills({
    required String userId,
    String? familyId,
  });

  Future<Result<void>> createVehicle({
    required String userId,
    String? familyId,
    required bool isFamilyShared,
    required String name,
    required String plateNumber,
    required int currentOdometerKm,
    required int serviceIntervalKm,
    required int serviceIntervalDays,
  });

  Future<Result<void>> updateOdometer({
    required VehicleEntity vehicle,
    required int newOdometerKm,
  });

  Future<Result<void>> recordMaintenance({
    required VehicleEntity vehicle,
    required String serviceTitle,
    required int odometerKm,
    required int costMinor,
    String? walletIdForExpense,
  });

  Future<Result<void>> createRecurringBill({
    required String userId,
    String? familyId,
    required String title,
    required String providerName,
    required int estimatedAmountMinor,
    required DateTime nextDueDate,
  });

  Future<Result<bool>> payRecurringBill({
    required String userId,
    required RecurringBillEntity bill,
    required int paidAmountMinor,
    required String walletId,
  });
}

final class UpdateOdometerParams {
  final VehicleEntity vehicle;
  final int newOdometerKm;

  const UpdateOdometerParams({required this.vehicle, required this.newOdometerKm});
}

class UpdateOdometerUseCase implements UseCase<void, UpdateOdometerParams> {
  final VehicleRepository _repository;
  const UpdateOdometerUseCase(this._repository);

  @override
  Future<Result<void>> call(UpdateOdometerParams params) async {
    if (params.newOdometerKm < params.vehicle.currentOdometerKm) {
      return const Err(
        ValidationFailure(
          message: 'Số Odometer mới không được nhỏ hơn số km hiện tại của phương tiện.',
        ),
      );
    }
    return _repository.updateOdometer(
      vehicle: params.vehicle,
      newOdometerKm: params.newOdometerKm,
    );
  }
}
