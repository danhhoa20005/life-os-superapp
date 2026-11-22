import 'dart:async';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../calendar/domain/entities/calendar_entities.dart';
import '../../../calendar/domain/repositories/calendar_repository.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../tasks/domain/repositories/task_repository.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../../vehicles/domain/entities/vehicle_entities.dart';
import '../../../vehicles/domain/repositories/vehicle_repository.dart';
import '../../domain/entities/dashboard_entities.dart';
import '../../domain/repositories/dashboard_repository.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  final TransactionRepository _transactionRepo;
  final TaskRepository _taskRepo;
  final CalendarRepository _calendarRepo;
  final VehicleRepository _vehicleRepo;

  const DashboardRepositoryImpl({
    required TransactionRepository transactionRepo,
    required TaskRepository taskRepo,
    required CalendarRepository calendarRepo,
    required VehicleRepository vehicleRepo,
  })  : _transactionRepo = transactionRepo,
        _taskRepo = taskRepo,
        _calendarRepo = calendarRepo,
        _vehicleRepo = vehicleRepo;

  @override
  Stream<Result<TodayDashboardEntity>> watchTodayDashboard({
    required String userId,
    String? familyId,
  }) {
    final now = DateTime.now();
    final monthKey = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

    final financePair = StreamCombiner.combine2(
      _transactionRepo.watchWallets(userId),
      _transactionRepo.watchTransactions(userId: userId, monthKey: monthKey),
      (w, t) => (wallets: w, txs: t),
    );

    final combined = StreamCombiner.combine4(
      financePair,
      _taskRepo.watchTasks(userId: userId, familyId: familyId),
      _calendarRepo.watchEvents(userId: userId, familyId: familyId),
      _vehicleRepo.watchVehicles(userId: userId, familyId: familyId),
      (fin, tasksRes, eventsRes, vehiclesRes) {
        final wallets = fin.wallets is Success<List<WalletEntity>>
            ? (fin.wallets as Success<List<WalletEntity>>).value
            : const <WalletEntity>[];
        final txs = fin.txs is Success<List<TransactionEntity>>
            ? (fin.txs as Success<List<TransactionEntity>>).value
            : const <TransactionEntity>[];
        final tasks = tasksRes is Success<List<TaskEntity>>
            ? tasksRes.value
            : const <TaskEntity>[];
        final events = eventsRes is Success<List<CalendarEventEntity>>
            ? eventsRes.value
            : const <CalendarEventEntity>[];
        final vehicles = vehiclesRes is Success<List<VehicleEntity>>
            ? vehiclesRes.value
            : const <VehicleEntity>[];

        final summary = FinanceOverviewSummary.compute(wallets: wallets, transactions: txs);
        final todayStart = DateTime(now.year, now.month, now.day);
        var todayExpense = 0;
        final alerts = <DashboardAlertItem>[];

        for (final tx in txs) {
          if (tx.verification == TransactionVerification.provisional) {
            alerts.add(
              DashboardAlertItem(
                id: 'prov_${tx.id}',
                category: 'provisional_tx',
                title: 'Giao dịch chờ duyệt: ${VndAmount.format(tx.amountMinor)}',
                subtitle: '${tx.merchant} · Nhấn vào tab Tài chính để xác nhận',
                isUrgent: true,
              ),
            );
          } else if (tx.isConfirmedInLedger &&
              !tx.isReversed &&
              tx.kind == TransactionKind.expense) {
            if (!tx.occurredAt.isBefore(todayStart)) {
              todayExpense += tx.amountMinor;
            }
            if (tx.isVehicleMaintenanceHint && vehicles.isNotEmpty) {
              alerts.add(
                DashboardAlertItem(
                  id: 'smart_${tx.id}',
                  category: 'smart_rule',
                  title: 'Gợi ý thông minh: Cập nhật bảo dưỡng cho ${vehicles.first.name}',
                  subtitle:
                      'Từ khoản chi "${tx.merchant}" (${VndAmount.format(tx.amountMinor)})',
                ),
              );
            }
          }
        }

        var dueVehCount = 0;
        for (final v in vehicles) {
          final state = v.dueStateAt(now);
          if (state != VehicleDueState.healthy) {
            dueVehCount += 1;
            alerts.add(
              DashboardAlertItem(
                id: 'veh_${v.id}',
                category: 'vehicle_due',
                title: state == VehicleDueState.overdue
                    ? 'Quá hạn bảo dưỡng: ${v.name}'
                    : 'Sắp đến hạn bảo dưỡng: ${v.name}',
                subtitle: 'Còn ${v.remainingKm} km · Hạn tiếp theo tại ${v.nextDueKm} km',
                isUrgent: state == VehicleDueState.overdue,
              ),
            );
          }
        }

        final openTasks = tasks
            .where((t) =>
                t.status != TaskWorkflowStatus.done && t.status != TaskWorkflowStatus.declined)
            .length;
        final proposedForMe = tasks
            .where((t) => t.assigneeId == userId && t.status == TaskWorkflowStatus.proposed)
            .length;
        final upcomingEvents = events.where((e) => !e.endsAt.isBefore(now)).length;

        return Success<TodayDashboardEntity>(
          TodayDashboardEntity(
            netWorthMinor: summary.netWorthMinor,
            todayExpenseMinor: todayExpense,
            monthlyExpenseMinor: summary.monthlyExpenseMinor,
            monthlyIncomeMinor: summary.monthlyIncomeMinor,
            provisionalPendingCount: summary.provisionalCount,
            openTasksCount: openTasks,
            proposedTasksForMeCount: proposedForMe,
            upcomingEventsCount: upcomingEvents,
            dueVehiclesCount: dueVehCount,
            highlights: alerts.take(8).toList(growable: false),
          ),
        );
      },
    );

    return combined.transform(
      StreamTransformer.fromHandlers(
        handleError: (Object e, StackTrace _, EventSink<Result<TodayDashboardEntity>> sink) {
          sink.add(Err(ErrorMapper.map(e)));
        },
      ),
    );
  }
}
