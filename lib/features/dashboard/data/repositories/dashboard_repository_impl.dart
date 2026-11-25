import 'dart:async';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../calendar/domain/entities/calendar_entities.dart';
import '../../../calendar/domain/repositories/calendar_repository.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../tasks/domain/repositories/task_repository.dart';
import '../../../transactions/domain/entities/financial_aggregation_engine.dart';
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
  final DateTime Function()? _clock;
  final Stream<void>? _boundaryTickStream;

  const DashboardRepositoryImpl({
    required TransactionRepository transactionRepo,
    required TaskRepository taskRepo,
    required CalendarRepository calendarRepo,
    required VehicleRepository vehicleRepo,
    DateTime Function()? clock,
    Stream<void>? boundaryTickStream,
  }) : _transactionRepo = transactionRepo,
       _taskRepo = taskRepo,
       _calendarRepo = calendarRepo,
       _vehicleRepo = vehicleRepo,
       _clock = clock,
       _boundaryTickStream = boundaryTickStream;

  DateTime _now() => (_clock ?? DateTime.now)();

  static String _monthKeyFor(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}';

  static String _dayKeyFor(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  @override
  Stream<Result<TodayDashboardEntity>> watchTodayDashboard({
    required String userId,
    String? familyId,
  }) {
    return Stream<Result<TodayDashboardEntity>>.multi((controller) {
      final initialNow = _now();
      var activeMonthKey = _monthKeyFor(initialNow);
      var activeDayKey = _dayKeyFor(initialNow);
      var activeTzOffset = initialNow.timeZoneOffset;

      Result<List<WalletEntity>>? lastWallets;
      Result<List<TransactionEntity>>? lastTxs;
      Result<List<TaskEntity>>? lastTasks;
      Result<List<CalendarEventEntity>>? lastEvents;
      Result<List<VehicleEntity>>? lastVehicles;

      var lastPersistedNetWorth = -1;
      var lastPersistedSummaryKey = '';

      StreamSubscription<Result<List<WalletEntity>>>? subWallets;
      StreamSubscription<Result<List<TransactionEntity>>>? subTxs;
      StreamSubscription<Result<List<TaskEntity>>>? subTasks;
      StreamSubscription<Result<List<CalendarEventEntity>>>? subEvents;
      StreamSubscription<Result<List<VehicleEntity>>>? subVehicles;
      StreamSubscription<void>? subBoundaryTicks;
      Timer? midnightTimer;

      late void Function(String monthKey) subscribeMonthTxs;
      late void Function(DateTime refNow) scheduleMidnightTimer;

      void emitComputedOrError(DateTime now) {
        if (controller.isClosed) return;
        if (lastWallets == null ||
            lastTxs == null ||
            lastTasks == null ||
            lastEvents == null ||
            lastVehicles == null) {
          return;
        }

        // Propagate errors honestly — NEVER fall back to empty list / 0 VND!
        if (lastWallets is Err<List<WalletEntity>>) {
          controller.add(Err((lastWallets! as Err<List<WalletEntity>>).failure));
          return;
        }
        if (lastTxs is Err<List<TransactionEntity>>) {
          controller.add(
            Err((lastTxs! as Err<List<TransactionEntity>>).failure),
          );
          return;
        }
        if (lastTasks is Err<List<TaskEntity>>) {
          controller.add(Err((lastTasks! as Err<List<TaskEntity>>).failure));
          return;
        }
        if (lastEvents is Err<List<CalendarEventEntity>>) {
          controller.add(
            Err((lastEvents! as Err<List<CalendarEventEntity>>).failure),
          );
          return;
        }
        if (lastVehicles is Err<List<VehicleEntity>>) {
          controller.add(
            Err((lastVehicles! as Err<List<VehicleEntity>>).failure),
          );
          return;
        }

        final wallets = (lastWallets! as Success<List<WalletEntity>>).value;
        final txs = (lastTxs! as Success<List<TransactionEntity>>).value;
        final tasks = (lastTasks! as Success<List<TaskEntity>>).value;
        final events = (lastEvents! as Success<List<CalendarEventEntity>>).value;
        final vehicles = (lastVehicles! as Success<List<VehicleEntity>>).value;

        final agg = FinancialAggregationEngine.forMonthKey(
          txs,
          activeMonthKey,
          wallets: wallets,
        );
        final summary = agg.toOverviewSummary();

        if (wallets.isNotEmpty &&
            summary.netWorthMinor != lastPersistedNetWorth) {
          lastPersistedNetWorth = summary.netWorthMinor;
          unawaited(
            _transactionRepo.saveNetWorthSnapshot(
              userId: userId,
              monthKey: activeMonthKey,
              summary: summary,
            ),
          );
        }

        final summarySig =
            '$activeMonthKey|${agg.incomeMinor}|${agg.grossExpenseMinor}|${agg.refundMinor}|${agg.internalTransferMinor}|${agg.totalEvaluatedCount}';
        if (summarySig != lastPersistedSummaryKey) {
          lastPersistedSummaryKey = summarySig;
          unawaited(
            _transactionRepo.saveMonthlySummary(
              userId: userId,
              monthKey: activeMonthKey,
              summary: agg,
            ),
          );
        }

        final dailyWindow =
            FinancialAggregationEngine.computeRecentDailyCashflow(
              txs,
              referenceNow: now,
              days: 7,
            );

        final alerts = <DashboardAlertItem>[];
        for (final tx in txs) {
          if (tx.verification == TransactionVerification.provisional ||
              tx.verification == TransactionVerification.needsReview) {
            alerts.add(
              DashboardAlertItem(
                id: 'prov_${tx.id}',
                category: 'provisional_tx',
                title:
                    'Giao dịch chờ duyệt: ${VndAmount.format(tx.amountMinor)}',
                subtitle: '${tx.merchant} · Nhấn vào tab Tài chính để xác nhận',
                isUrgent: true,
              ),
            );
          } else if (tx.isConfirmedInLedger &&
              !tx.isReversed &&
              tx.kind == TransactionKind.expense &&
              tx.isVehicleMaintenanceHint &&
              vehicles.isNotEmpty) {
            alerts.add(
              DashboardAlertItem(
                id: 'smart_${tx.id}',
                category: 'smart_rule',
                title:
                    'Gợi ý thông minh: Cập nhật bảo dưỡng cho ${vehicles.first.name}',
                subtitle:
                    'Từ khoản chi "${tx.merchant}" (${VndAmount.format(tx.amountMinor)})',
              ),
            );
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
                subtitle:
                    'Còn ${v.remainingKm} km · Hạn tiếp theo tại ${v.nextDueKm} km',
                isUrgent: state == VehicleDueState.overdue,
              ),
            );
          }
        }

        // Dynamic Safe-to-Spend per day for the rest of the current month
        final lastDayOfMonth = DateTime(now.year, now.month + 1, 0).day;
        final remainingDays = (lastDayOfMonth - now.day + 1).clamp(1, 31);
        final spendEnvelope = summary.monthlyIncomeMinor > 0
            ? (summary.monthlyIncomeMinor * 80) ~/ 100
            : (summary.liquidAssetsMinor > 0
                  ? summary.liquidAssetsMinor ~/ 4
                  : 0);
        final remainingBudget = spendEnvelope - summary.monthlyExpenseMinor;
        final safeToSpendDaily = remainingBudget > 0
            ? remainingBudget ~/ remainingDays
            : 0;

        final openTasks = tasks
            .where(
              (t) =>
                  t.status != TaskWorkflowStatus.done &&
                  t.status != TaskWorkflowStatus.declined,
            )
            .length;
        final proposedForMe = tasks
            .where(
              (t) =>
                  t.assigneeId == userId &&
                  t.status == TaskWorkflowStatus.proposed,
            )
            .length;
        final upcomingEvents = events
            .where((e) => !e.endsAt.isBefore(now))
            .length;

        final topCats = summary.sortedCategoryShares
            .take(3)
            .map(
              (s) => DashboardCategorySlice(
                categoryName: s.categoryName,
                amountMinor: s.amountMinor,
                sharePct: s.sharePct,
              ),
            )
            .toList(growable: false);

        controller.add(
          Success<TodayDashboardEntity>(
            TodayDashboardEntity(
              netWorthMinor: summary.netWorthMinor,
              liquidAssetsMinor: summary.liquidAssetsMinor,
              savingsAssetsMinor: summary.savingsAssetsMinor,
              creditDebtMinor: summary.creditLiabilityMinor,
              walletCount: wallets.length,
              todayExpenseMinor: dailyWindow.todayExpenseMinor,
              monthlyExpenseMinor: summary.monthlyExpenseMinor,
              monthlyIncomeMinor: summary.monthlyIncomeMinor,
              dailySafeToSpendMinor: safeToSpendDaily,
              financialHealthScore: summary.financialHealthScore,
              savingsRatePct: summary.savingsRatePct,
              provisionalPendingCount: agg.unconfirmedCount,
              openTasksCount: openTasks,
              proposedTasksForMeCount: proposedForMe,
              upcomingEventsCount: upcomingEvents,
              dueVehiclesCount: dueVehCount,
              recent7DayExpensesMinor: dailyWindow.dailyExpensesMinor,
              recent7DayIncomesMinor: dailyWindow.dailyIncomesMinor,
              topCategories: topCats,
              highlights: alerts.take(8).toList(growable: false),
            ),
          ),
        );
      }

      void checkBoundaryAndRefresh() {
        if (controller.isClosed) return;
        final currentNow = _now();
        final nextMonthKey = _monthKeyFor(currentNow);
        final nextDayKey = _dayKeyFor(currentNow);
        final nextTzOffset = currentNow.timeZoneOffset;

        if (nextMonthKey != activeMonthKey) {
          activeMonthKey = nextMonthKey;
          activeDayKey = nextDayKey;
          activeTzOffset = nextTzOffset;
          lastTxs = null;
          subscribeMonthTxs(activeMonthKey);
          scheduleMidnightTimer(currentNow);
          return;
        }

        if (nextDayKey != activeDayKey || nextTzOffset != activeTzOffset) {
          activeDayKey = nextDayKey;
          activeTzOffset = nextTzOffset;
          scheduleMidnightTimer(currentNow);
        }

        emitComputedOrError(currentNow);
      }

      scheduleMidnightTimer = (DateTime refNow) {
        midnightTimer?.cancel();
        if (controller.isClosed) return;
        final nextMidnight = refNow.isUtc
            ? DateTime.utc(refNow.year, refNow.month, refNow.day + 1)
            : DateTime(refNow.year, refNow.month, refNow.day + 1);
        final delay =
            nextMidnight.difference(refNow) + const Duration(milliseconds: 50);
        if (delay <= Duration.zero) return;
        midnightTimer = Timer(delay, checkBoundaryAndRefresh);
      };

      subscribeMonthTxs = (String monthKey) {
        unawaited(subTxs?.cancel());
        subTxs = _transactionRepo
            .watchAllTransactionsForAggregation(
              userId: userId,
              monthKey: monthKey,
            )
            .listen(
              (txsRes) {
                lastTxs = txsRes;
                checkBoundaryAndRefresh();
              },
              onError: (Object e, StackTrace _) {
                if (!controller.isClosed) {
                  controller.add(Err(ErrorMapper.map(e)));
                }
              },
            );
      };

      subWallets = _transactionRepo
          .watchWallets(userId)
          .listen(
            (wRes) {
              lastWallets = wRes;
              checkBoundaryAndRefresh();
            },
            onError: (Object e, StackTrace _) {
              if (!controller.isClosed) {
                controller.add(Err(ErrorMapper.map(e)));
              }
            },
          );

      subscribeMonthTxs(activeMonthKey);

      subTasks = _taskRepo
          .watchTasks(userId: userId, familyId: familyId)
          .listen(
            (tRes) {
              lastTasks = tRes;
              checkBoundaryAndRefresh();
            },
            onError: (Object e, StackTrace _) {
              if (!controller.isClosed) {
                controller.add(Err(ErrorMapper.map(e)));
              }
            },
          );

      subEvents = _calendarRepo
          .watchEvents(userId: userId, familyId: familyId)
          .listen(
            (eRes) {
              lastEvents = eRes;
              checkBoundaryAndRefresh();
            },
            onError: (Object e, StackTrace _) {
              if (!controller.isClosed) {
                controller.add(Err(ErrorMapper.map(e)));
              }
            },
          );

      subVehicles = _vehicleRepo
          .watchVehicles(userId: userId, familyId: familyId)
          .listen(
            (vRes) {
              lastVehicles = vRes;
              checkBoundaryAndRefresh();
            },
            onError: (Object e, StackTrace _) {
              if (!controller.isClosed) {
                controller.add(Err(ErrorMapper.map(e)));
              }
            },
          );

      if (_boundaryTickStream != null) {
        subBoundaryTicks = _boundaryTickStream.listen((_) {
          checkBoundaryAndRefresh();
        });
      }

      scheduleMidnightTimer(initialNow);

      controller.onCancel = () async {
        midnightTimer?.cancel();
        await subBoundaryTicks?.cancel();
        await subWallets?.cancel();
        await subTxs?.cancel();
        await subTasks?.cancel();
        await subEvents?.cancel();
        await subVehicles?.cancel();
      };
    });
  }
}
