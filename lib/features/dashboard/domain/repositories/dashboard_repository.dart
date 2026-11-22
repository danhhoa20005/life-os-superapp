import '../../../../core/error/app_exception.dart';
import '../entities/dashboard_entities.dart';

abstract interface class DashboardRepository {
  Stream<Result<TodayDashboardEntity>> watchTodayDashboard({
    required String userId,
    String? familyId,
  });
}
