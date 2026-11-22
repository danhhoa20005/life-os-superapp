import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_assets.dart';
import '../core/di/dependency_injection.dart';
import '../features/authentication/presentation/bloc/auth_bloc.dart';
import '../features/authentication/presentation/bloc/auth_state.dart';
import '../features/authentication/presentation/pages/account_profile_page.dart';
import '../features/authentication/presentation/pages/auth_pages.dart';
import '../features/authentication/presentation/pages/splash_page.dart';
import '../features/budgets/presentation/bloc/budget_bloc.dart';
import '../features/calendar/presentation/bloc/calendar_bloc.dart';
import '../features/calendar/presentation/pages/planning_page.dart';
import '../features/dashboard/presentation/bloc/dashboard_bloc.dart';
import '../features/dashboard/presentation/pages/today_page.dart';
import '../features/family/presentation/bloc/family_bloc.dart';
import '../features/family/presentation/pages/family_page.dart';
import '../features/notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../features/notifications/presentation/pages/notifications_privacy_page.dart';
import '../features/tasks/presentation/bloc/task_bloc.dart';
import '../features/transactions/presentation/bloc/transaction_bloc.dart';
import '../features/transactions/presentation/bloc/transaction_event.dart';
import '../features/transactions/presentation/pages/finance_page.dart';
import '../features/vehicles/presentation/bloc/vehicle_bloc.dart';
import '../features/vehicles/presentation/pages/assets_page.dart';
import 'theme/app_colors.dart';
import 'theme/app_spacing.dart';

/// Pure Flutter `Listenable` adapter bridging `AuthBloc.stream` to `GoRouter.refreshListenable`.
/// Holds zero business state.
class BlocRouterRefreshStream implements Listenable {
  final List<VoidCallback> _listeners = <VoidCallback>[];
  late final StreamSubscription<dynamic> _subscription;

  BlocRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) {
      for (final listener in List<VoidCallback>.from(_listeners)) {
        listener();
      }
    });
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  Future<void> dispose() => _subscription.cancel();
}

GoRouter createAppRouter(AuthBloc authBloc, BlocRouterRefreshStream refreshStream) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshStream,
    redirect: (context, state) {
      final authState = authBloc.state;
      final loc = state.matchedLocation;

      if (authState.status == AuthStatus.unknown) {
        return loc == '/splash' ? null : '/splash';
      }

      final isPublicAuthRoute = loc == '/login' || loc == '/register';
      if (authState.status == AuthStatus.unauthenticated) {
        return isPublicAuthRoute ? null : '/login';
      }

      final user = authState.user;
      if (user != null && !user.onboardingCompleted) {
        return loc == '/onboarding' ? null : '/onboarding';
      }

      if (loc == '/splash' || isPublicAuthRoute || loc == '/onboarding') {
        return '/today';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingPrivacyPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return _AuthenticatedAdaptiveShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/today', builder: (_, __) => const TodayPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/finance', builder: (_, __) => const FinancePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/planning', builder: (_, __) => const PlanningPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/family', builder: (_, __) => const FamilyPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/assets', builder: (_, __) => const AssetsPage()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/account-profile',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return const AccountProfilePage();
        },
      ),
      GoRoute(
        path: '/notifications-privacy',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return MultiBlocProvider(
            providers: [
              BlocProvider<TransactionListBloc>(
                create: (_) => sl<TransactionListBloc>()
                  ..add(TransactionsSubscriptionRequested(userId: user.id)),
              ),
              BlocProvider<NotificationIngestionBloc>(
                create: (_) => sl<NotificationIngestionBloc>()
                  ..add(NotificationsCenterStarted(user.id)),
              ),
            ],
            child: const NotificationsPrivacyPage(),
          );
        },
      ),
    ],
  );
}

class _AuthenticatedAdaptiveShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _AuthenticatedAdaptiveShell({required this.navigationShell});

  static const List<({IconData icon, IconData activeIcon, String assetPath, String label})>
      _tabs = [
    (
      icon: Icons.wb_sunny_outlined,
      activeIcon: Icons.wb_sunny_rounded,
      assetPath: AppAssets.icNavToday,
      label: 'Hôm nay',
    ),
    (
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      assetPath: AppAssets.icNavFinance,
      label: 'Tài chính',
    ),
    (
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
      assetPath: AppAssets.icNavCalendar,
      label: 'Lịch & Việc',
    ),
    (
      icon: Icons.groups_outlined,
      activeIcon: Icons.groups_rounded,
      assetPath: AppAssets.icNavFamily,
      label: 'Gia đình',
    ),
    (
      icon: Icons.two_wheeler_outlined,
      activeIcon: Icons.two_wheeler_rounded,
      assetPath: AppAssets.icNavAssets,
      label: 'Tài sản',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final monthKey = TransactionListBloc.currentMonthKey();
    final scopeKey = ValueKey('shell_${user.id}_${user.activeFamilyId ?? "none"}');

    return MultiBlocProvider(
      key: scopeKey,
      providers: [
        BlocProvider<DashboardBloc>(
          create: (_) => sl<DashboardBloc>()
            ..add(DashboardWatchStarted(userId: user.id, familyId: user.activeFamilyId)),
        ),
        BlocProvider<TransactionListBloc>(
          create: (_) => sl<TransactionListBloc>()
            ..add(TransactionsSubscriptionRequested(userId: user.id, monthKey: monthKey)),
        ),
        BlocProvider<TransactionActionBloc>(
          create: (_) => sl<TransactionActionBloc>(),
        ),
        BlocProvider<BudgetBloc>(
          create: (_) => sl<BudgetBloc>()
            ..add(
              BudgetsSubscriptionRequested(
                userId: user.id,
                monthKey: monthKey,
                familyId: user.activeFamilyId,
              ),
            ),
        ),
        BlocProvider<FamilyBloc>(
          create: (_) => sl<FamilyBloc>()
            ..add(
              FamilySubscriptionRequested(
                userId: user.id,
                preferredFamilyId: user.activeFamilyId,
              ),
            ),
        ),
        BlocProvider<CalendarBloc>(
          create: (_) => sl<CalendarBloc>()
            ..add(CalendarWatchStarted(userId: user.id, familyId: user.activeFamilyId)),
        ),
        BlocProvider<TaskBloc>(
          create: (_) => sl<TaskBloc>()
            ..add(TasksWatchStarted(userId: user.id, familyId: user.activeFamilyId)),
        ),
        BlocProvider<VehicleBloc>(
          create: (_) => sl<VehicleBloc>()
            ..add(VehiclesWatchStarted(userId: user.id, familyId: user.activeFamilyId)),
        ),
        BlocProvider<NotificationIngestionBloc>(
          create: (_) => sl<NotificationIngestionBloc>()
            ..add(
              NotificationsCenterStarted(
                user.id,
                defaultWalletId: 'wallet_bank_default',
              ),
            ),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= AppSpacing.tabletBreakpoint;
          final c = TammySemanticColors.of(context);

          if (isWide) {
            return Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    leading: const Padding(
                      padding: EdgeInsets.only(top: 12, bottom: 8),
                      child: BrandLogoMark(size: 40, borderRadius: 12),
                    ),
                    selectedIndex: navigationShell.currentIndex,
                    onDestinationSelected: (idx) => navigationShell.goBranch(
                      idx,
                      initialLocation: idx == navigationShell.currentIndex,
                    ),
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: c.surface,
                    indicatorColor: c.primarySubtle,
                    selectedIconTheme: IconThemeData(color: c.primary),
                    selectedLabelTextStyle: TextStyle(
                      color: c.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    destinations: _tabs
                        .map(
                          (t) => NavigationRailDestination(
                            icon: Opacity(
                              opacity: 0.78,
                              child: BananaGlassIcon(
                                assetPath: t.assetPath,
                                fallbackIcon: t.icon,
                                size: 28,
                                borderRadius: 9,
                              ),
                            ),
                            selectedIcon: BananaGlassIcon(
                              assetPath: t.assetPath,
                              fallbackIcon: t.activeIcon,
                              size: 30,
                              borderRadius: 10,
                              isSelected: true,
                            ),
                            label: Text(t.label),
                          ),
                        )
                        .toList(),
                  ),
                  VerticalDivider(width: 1, thickness: 0.8, color: c.separator),
                  Expanded(child: navigationShell),
                ],
              ),
            );
          }

          return Scaffold(
            extendBody: false,
            body: navigationShell,
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: c.separator.withValues(alpha: 0.7),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: NavigationBar(
                      height: 66,
                      selectedIndex: navigationShell.currentIndex,
                      onDestinationSelected: (idx) => navigationShell.goBranch(
                        idx,
                        initialLocation: idx == navigationShell.currentIndex,
                      ),
                      destinations: _tabs
                          .map(
                            (t) => NavigationDestination(
                              icon: Opacity(
                                opacity: 0.78,
                                child: BananaGlassIcon(
                                  assetPath: t.assetPath,
                                  fallbackIcon: t.icon,
                                  size: 26,
                                  borderRadius: 9,
                                ),
                              ),
                              selectedIcon: BananaGlassIcon(
                                assetPath: t.assetPath,
                                fallbackIcon: t.activeIcon,
                                size: 28,
                                borderRadius: 10,
                                isSelected: true,
                              ),
                              label: t.label,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
