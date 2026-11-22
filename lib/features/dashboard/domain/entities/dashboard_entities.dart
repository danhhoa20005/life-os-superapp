import 'package:equatable/equatable.dart';

class DashboardCategorySlice extends Equatable {
  final String categoryName;
  final int amountMinor;
  final double sharePct;

  const DashboardCategorySlice({
    required this.categoryName,
    required this.amountMinor,
    required this.sharePct,
  });

  @override
  List<Object?> get props => [categoryName, amountMinor, sharePct];
}

class DashboardAlertItem extends Equatable {
  final String id;
  final String category; // 'provisional_tx' | 'vehicle_due' | 'bill_due' | 'smart_rule'
  final String title;
  final String subtitle;
  final bool isUrgent;

  const DashboardAlertItem({
    required this.id,
    required this.category,
    required this.title,
    required this.subtitle,
    this.isUrgent = false,
  });

  @override
  List<Object?> get props => [id, category, title, subtitle, isUrgent];
}

class TodayDashboardEntity extends Equatable {
  final int netWorthMinor;
  final int liquidAssetsMinor;
  final int savingsAssetsMinor;
  final int creditDebtMinor;
  final int walletCount;
  final int todayExpenseMinor;
  final int monthlyExpenseMinor;
  final int monthlyIncomeMinor;
  final int dailySafeToSpendMinor;
  final int financialHealthScore;
  final double savingsRatePct;
  final int provisionalPendingCount;
  final int openTasksCount;
  final int proposedTasksForMeCount;
  final int upcomingEventsCount;
  final int dueVehiclesCount;
  final List<int> recent7DayExpensesMinor;
  final List<int> recent7DayIncomesMinor;
  final List<DashboardCategorySlice> topCategories;
  final List<DashboardAlertItem> highlights;

  const TodayDashboardEntity({
    required this.netWorthMinor,
    this.liquidAssetsMinor = 0,
    this.savingsAssetsMinor = 0,
    this.creditDebtMinor = 0,
    this.walletCount = 0,
    required this.todayExpenseMinor,
    required this.monthlyExpenseMinor,
    required this.monthlyIncomeMinor,
    this.dailySafeToSpendMinor = 0,
    this.financialHealthScore = 75,
    this.savingsRatePct = 0.0,
    required this.provisionalPendingCount,
    required this.openTasksCount,
    required this.proposedTasksForMeCount,
    required this.upcomingEventsCount,
    required this.dueVehiclesCount,
    this.recent7DayExpensesMinor = const [0, 0, 0, 0, 0, 0, 0],
    this.recent7DayIncomesMinor = const [0, 0, 0, 0, 0, 0, 0],
    this.topCategories = const [],
    this.highlights = const [],
  });

  int get netCashFlowMinor => monthlyIncomeMinor - monthlyExpenseMinor;

  static const TodayDashboardEntity empty = TodayDashboardEntity(
    netWorthMinor: 0,
    todayExpenseMinor: 0,
    monthlyExpenseMinor: 0,
    monthlyIncomeMinor: 0,
    provisionalPendingCount: 0,
    openTasksCount: 0,
    proposedTasksForMeCount: 0,
    upcomingEventsCount: 0,
    dueVehiclesCount: 0,
  );

  @override
  List<Object?> get props => [
        netWorthMinor,
        liquidAssetsMinor,
        savingsAssetsMinor,
        creditDebtMinor,
        walletCount,
        todayExpenseMinor,
        monthlyExpenseMinor,
        monthlyIncomeMinor,
        dailySafeToSpendMinor,
        financialHealthScore,
        savingsRatePct,
        provisionalPendingCount,
        openTasksCount,
        proposedTasksForMeCount,
        upcomingEventsCount,
        dueVehiclesCount,
        recent7DayExpensesMinor,
        recent7DayIncomesMinor,
        topCategories,
        highlights,
      ];
}
