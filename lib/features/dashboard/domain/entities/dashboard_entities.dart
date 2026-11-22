import 'package:equatable/equatable.dart';

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
  final int todayExpenseMinor;
  final int monthlyExpenseMinor;
  final int monthlyIncomeMinor;
  final int provisionalPendingCount;
  final int openTasksCount;
  final int proposedTasksForMeCount;
  final int upcomingEventsCount;
  final int dueVehiclesCount;
  final List<DashboardAlertItem> highlights;

  const TodayDashboardEntity({
    required this.netWorthMinor,
    required this.todayExpenseMinor,
    required this.monthlyExpenseMinor,
    required this.monthlyIncomeMinor,
    required this.provisionalPendingCount,
    required this.openTasksCount,
    required this.proposedTasksForMeCount,
    required this.upcomingEventsCount,
    required this.dueVehiclesCount,
    this.highlights = const [],
  });

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
        todayExpenseMinor,
        monthlyExpenseMinor,
        monthlyIncomeMinor,
        provisionalPendingCount,
        openTasksCount,
        proposedTasksForMeCount,
        upcomingEventsCount,
        dueVehiclesCount,
        highlights,
      ];
}
