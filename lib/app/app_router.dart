import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_assets.dart';
import '../core/di/dependency_injection.dart';
import '../core/services/fcm_banking_messaging_service.dart';
import '../core/services/native_alarm_scheduler_bridge.dart';
import '../core/services/native_home_widget_bridge.dart';
import '../core/utils/smart_quick_entry_parser.dart';
import '../core/utils/vnd_amount.dart';
import '../core/widgets/lifeos_design_system.dart';
import '../core/widgets/voice_smart_capture_sheet.dart';
import 'theme/lifeos_brand_colors.dart';
import '../features/authentication/presentation/bloc/auth_bloc.dart';
import '../features/authentication/presentation/bloc/auth_state.dart';
import '../features/authentication/presentation/pages/account_profile_page.dart';
import '../features/authentication/presentation/pages/auth_pages.dart';
import '../features/authentication/presentation/pages/splash_page.dart';
import '../features/budgets/presentation/bloc/budget_bloc.dart';
import '../features/calendar/domain/entities/calendar_entities.dart';
import '../features/calendar/presentation/bloc/calendar_bloc.dart';
import '../features/calendar/presentation/pages/event_detail_and_alarm_pages.dart';
import '../features/calendar/presentation/pages/planning_page.dart';
import '../features/daily_life/presentation/bloc/daily_life_bloc.dart';
import '../features/daily_life/presentation/pages/health_medical_hub_page.dart';
import '../features/daily_life/presentation/pages/home_living_utilities_page.dart';
import '../features/daily_life/presentation/pages/kitchen_groceries_page.dart';
import '../features/daily_life/presentation/pages/smart_notes_salary_page.dart';
import '../features/daily_life/presentation/pages/super_app_directory_page.dart';
import '../features/dashboard/presentation/bloc/dashboard_bloc.dart';
import '../features/dashboard/presentation/pages/home_widgets_studio_page.dart';
import '../features/dashboard/presentation/pages/today_page.dart';
import '../features/documents/presentation/bloc/document_vault_bloc.dart';
import '../features/documents/presentation/pages/family_documents_page.dart';
import '../features/family/presentation/bloc/family_bloc.dart';
import '../features/family/presentation/pages/family_funds_page.dart';
import '../features/family/presentation/pages/family_page.dart';
import '../features/notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../features/notifications/presentation/pages/activity_and_settings_pages.dart';
import '../features/notifications/presentation/pages/notifications_privacy_page.dart';
import '../features/pro_utilities/presentation/bloc/pro_utilities_bloc.dart';
import '../features/pro_utilities/presentation/pages/habits_focus_page.dart';
import '../features/pro_utilities/presentation/pages/pro_utilities_hub_page.dart';
import '../features/pro_utilities/presentation/pages/social_ledger_travel_page.dart';
import '../features/pro_utilities/presentation/pages/subscriptions_warranty_page.dart';
import '../features/pro_utilities/presentation/pages/wealth_tools_page.dart';
import '../features/tasks/presentation/bloc/task_bloc.dart';
import '../features/tasks/presentation/pages/tasks_board_page.dart';
import '../features/transactions/domain/entities/transaction_entities.dart';
import '../features/transactions/presentation/bloc/transaction_bloc.dart';
import '../features/transactions/presentation/bloc/transaction_event.dart';
import '../features/transactions/presentation/pages/auto_tx_and_report_pages.dart';
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

GoRouter createAppRouter(
  AuthBloc authBloc,
  BlocRouterRefreshStream refreshStream,
) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshStream,
    redirect: (context, state) {
      final authState = authBloc.state;
      final loc = state.matchedLocation;

      if (authState.status == AuthStatus.unknown) {
        return loc == '/splash' ? null : '/splash';
      }

      final isPublicAuthRoute =
          loc == '/welcome' ||
          loc == '/login' ||
          loc == '/register' ||
          loc == '/forgot-password' ||
          loc == '/verify-otp' ||
          loc == '/reset-password';
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
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomePage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, state) => ForgotPasswordPage(
          initialEmail: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/verify-otp',
        builder: (_, state) => VerifyOtpPage(
          email: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, __) => const ResetPasswordPage(),
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
              GoRoute(
                path: '/finance',
                builder: (_, __) => const FinancePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/planning',
                builder: (_, __) => const PlanningPage(),
              ),
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
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const NotificationsPrivacyPage(),
          );
        },
      ),
      GoRoute(
        path: '/home-widgets',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const HomeWidgetsStudioPage(),
          );
        },
      ),
      GoRoute(
        path: '/event-detail',
        builder: (context, state) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: EventDetailPage(
              initialEvent: state.extra is CalendarEventEntity
                  ? state.extra as CalendarEventEntity
                  : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/event-alarm',
        builder: (context, state) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return EventAlarmPage(
            event: state.extra is CalendarEventEntity
                ? state.extra as CalendarEventEntity
                : null,
          );
        },
      ),
      GoRoute(
        path: '/tasks-board',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const TasksBoardPage(),
          );
        },
      ),
      GoRoute(
        path: '/auto-tx-review',
        builder: (context, state) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: AutoTransactionReviewPage(
              initialTransaction: state.extra is TransactionEntity
                  ? state.extra as TransactionEntity
                  : null,
              initialTransactionId: state.uri.queryParameters['txId'],
            ),
          );
        },
      ),
      GoRoute(
        path: '/finance-report',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const FinanceReportPage(),
          );
        },
      ),
      GoRoute(
        path: '/family-funds',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const FamilyFundsPage(),
          );
        },
      ),
      GoRoute(
        path: '/family-documents',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const FamilyDocumentsPage(),
          );
        },
      ),
      GoRoute(
        path: '/activity-notifications',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const ActivityNotificationsPage(),
          );
        },
      ),
      GoRoute(
        path: '/settings-hub',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const SettingsHubPage(),
          );
        },
      ),
      GoRoute(
        path: '/pro-utilities',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const ProUtilitiesHubPage(),
          );
        },
      ),
      GoRoute(
        path: '/subscriptions-warranty',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const SubscriptionsWarrantyPage(),
          );
        },
      ),
      GoRoute(
        path: '/habits-focus',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const HabitsFocusPage(),
          );
        },
      ),
      GoRoute(
        path: '/social-ledger-travel',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const SocialLedgerTravelPage(),
          );
        },
      ),
      GoRoute(
        path: '/wealth-tools',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const WealthToolsPage(),
          );
        },
      ),
      GoRoute(
        path: '/super-app-hub',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const SuperAppDirectoryPage(),
          );
        },
      ),
      GoRoute(
        path: '/health-hub',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const HealthMedicalHubPage(),
          );
        },
      ),
      GoRoute(
        path: '/kitchen-groceries',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const KitchenGroceriesPage(),
          );
        },
      ),
      GoRoute(
        path: '/home-living',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const HomeLivingUtilitiesPage(),
          );
        },
      ),
      GoRoute(
        path: '/smart-notes-hub',
        builder: (context, _) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const SmartNotesSalaryPage(),
          );
        },
      ),
    ],
  );
}

/// Shared BLoC provider bundle used by both the main shell and pushed sub-routes.
class _ScopedAuthenticatedProviders extends StatelessWidget {
  final String userId;
  final String? familyId;
  final Widget child;

  const _ScopedAuthenticatedProviders({
    super.key,
    required this.userId,
    required this.familyId,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final monthKey = TransactionListBloc.currentMonthKey();
    return MultiBlocProvider(
      providers: [
        BlocProvider<DashboardBloc>(
          create: (_) => sl<DashboardBloc>()
            ..add(DashboardWatchStarted(userId: userId, familyId: familyId)),
        ),
        BlocProvider<TransactionListBloc>(
          create: (_) => sl<TransactionListBloc>()
            ..add(
              TransactionsSubscriptionRequested(
                userId: userId,
                monthKey: monthKey,
              ),
            ),
        ),
        BlocProvider<TransactionActionBloc>(
          create: (_) => sl<TransactionActionBloc>(),
        ),
        BlocProvider<BudgetBloc>(
          create: (_) => sl<BudgetBloc>()
            ..add(
              BudgetsSubscriptionRequested(
                userId: userId,
                monthKey: monthKey,
                familyId: familyId,
              ),
            ),
        ),
        BlocProvider<FamilyBloc>(
          create: (_) => sl<FamilyBloc>()
            ..add(
              FamilySubscriptionRequested(
                userId: userId,
                preferredFamilyId: familyId,
              ),
            ),
        ),
        BlocProvider<CalendarBloc>(
          create: (ctx) {
            final userName =
                ctx.read<AuthBloc>().state.user?.fullName ?? 'Cá nhân';
            return sl<CalendarBloc>()
              ..add(CalendarWatchStarted(userId: userId, familyId: familyId))
              ..add(
                GoogleCalendarSyncRequested(
                  userId: userId,
                  userName: userName,
                  interactive: false,
                ),
              );
          },
        ),
        BlocProvider<TaskBloc>(
          create: (_) =>
              sl<TaskBloc>()
                ..add(TasksWatchStarted(userId: userId, familyId: familyId)),
        ),
        BlocProvider<VehicleBloc>(
          create: (_) =>
              sl<VehicleBloc>()
                ..add(VehiclesWatchStarted(userId: userId, familyId: familyId)),
        ),
        BlocProvider<NotificationIngestionBloc>(
          create: (_) => sl<NotificationIngestionBloc>()
            ..add(
              NotificationsCenterStarted(
                userId,
                defaultWalletId: 'wallet_bank_default',
              ),
            ),
        ),
        BlocProvider<DocumentVaultBloc>(
          create: (_) => sl<DocumentVaultBloc>()
            ..add(
              DocumentVaultWatchStarted(userId: userId, familyId: familyId),
            ),
        ),
        BlocProvider<ProUtilitiesBloc>(
          create: (_) =>
              sl<ProUtilitiesBloc>()..add(ProUtilitiesWatchStarted(userId)),
        ),
        BlocProvider<DailyLifeBloc>(
          create: (_) =>
              sl<DailyLifeBloc>()..add(DailyLifeWatchStarted(userId)),
        ),
      ],
      child: child,
    );
  }
}

class _AuthenticatedAdaptiveShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _AuthenticatedAdaptiveShell({required this.navigationShell});

  static const List<
    ({
      int branchIndex,
      IconData icon,
      IconData activeIcon,
      String assetPath,
      String label,
    })
  >
  _tabs = [
    (
      branchIndex: 0,
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      assetPath: AppAssets.icNavToday,
      label: 'Hôm nay',
    ),
    (
      branchIndex: 1,
      icon: Icons.bar_chart_rounded,
      activeIcon: Icons.bar_chart_rounded,
      assetPath: AppAssets.icNavFinance,
      label: 'Tài chính',
    ),
    (
      branchIndex: 2,
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
      assetPath: AppAssets.icNavCalendar,
      label: 'Lịch & Việc',
    ),
    (
      branchIndex: 3,
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      assetPath: AppAssets.icNavFamily,
      label: 'Gia đình',
    ),
    (
      branchIndex: 4,
      icon: Icons.directions_car_outlined,
      activeIcon: Icons.directions_car_rounded,
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

    final scopeKey = ValueKey(
      'shell_${user.id}_${user.activeFamilyId ?? "none"}',
    );

    return _ScopedAuthenticatedProviders(
      key: scopeKey,
      userId: user.id,
      familyId: user.activeFamilyId,
      child: _HomeWidgetSyncAndIntentHost(
        navigationShell: navigationShell,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= AppSpacing.tabletBreakpoint;
            final c = TammySemanticColors.of(context);

            if (isWide) {
              return Scaffold(
                body: Row(
                  children: [
                    NavigationRail(
                      leading: Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 8),
                        child: Column(
                          children: [
                            const LifeOsLeafMark(size: 38, borderRadius: 12),
                            const SizedBox(height: 10),
                            IconButton.filled(
                              tooltip: 'Tạo nhanh LifeOS',
                              onPressed: () =>
                                  showLifeOsQuickCreateHub(context),
                              icon: const Icon(Icons.add_rounded),
                            ),
                          ],
                        ),
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
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      destinations: _tabs
                          .map(
                            (t) => NavigationRailDestination(
                              icon: Icon(t.icon),
                              selectedIcon: Icon(t.activeIcon),
                              label: Text(t.label),
                            ),
                          )
                          .toList(),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 0.8,
                      color: c.separator,
                    ),
                    Expanded(child: navigationShell),
                  ],
                ),
              );
            }

            // Mobile Floating Frosted Liquid-Glass Dock with BrandKit Gradient `+` Squircle
            // Ordered by daily thumb-zone ergonomics: Hôm nay & Tài chính on left, Planning/Family/Assets on right.
            final leftTabs = [_tabs[0], _tabs[1]]; // Hôm nay | Tài chính
            final rightTabs = [
              _tabs[2],
              _tabs[3],
              _tabs[4],
            ]; // Lịch & Việc | Gia đình | Tài sản
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Scaffold(
              extendBody: false,
              body: navigationShell,
              bottomNavigationBar: RepaintBoundary(
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          height: 66,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: c.surface.withValues(
                              alpha: isDark ? 0.92 : 0.95,
                            ),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(color: c.separator, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF0A140E,
                                ).withValues(alpha: isDark ? 0.36 : 0.08),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              for (final tab in leftTabs)
                                _BottomNavTabButton(
                                  icon: tab.icon,
                                  activeIcon: tab.activeIcon,
                                  label: tab.label,
                                  isSelected:
                                      navigationShell.currentIndex ==
                                      tab.branchIndex,
                                  onTap: () => navigationShell.goBranch(
                                    tab.branchIndex,
                                    initialLocation:
                                        tab.branchIndex ==
                                        navigationShell.currentIndex,
                                  ),
                                ),

                              // Signature Center BrandKit Gradient `+` Squircle Button (48×48 Tactile Target)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Tooltip(
                                  message: 'Thêm nhanh',
                                  child: Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(17),
                                    child: InkWell(
                                      key: const Key(
                                        'lifeos_center_quick_add_fab',
                                      ),
                                      borderRadius: BorderRadius.circular(17),
                                      onTap: () =>
                                          showLifeOsQuickCreateHub(context),
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            17,
                                          ),
                                          gradient: const LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: LifeOSBrandColors
                                                .appIconBgGradient,
                                            stops: LifeOSBrandColors
                                                .appIconBgStops,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.34,
                                            ),
                                            width: 1.1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: c.primary.withValues(
                                                alpha: 0.34,
                                              ),
                                              blurRadius: 14,
                                              offset: const Offset(0, 5),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.add_rounded,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              for (final tab in rightTabs)
                                _BottomNavTabButton(
                                  icon: tab.icon,
                                  activeIcon: tab.activeIcon,
                                  label: tab.label,
                                  isSelected:
                                      navigationShell.currentIndex ==
                                      tab.branchIndex,
                                  onTap: () => navigationShell.goBranch(
                                    tab.branchIndex,
                                    initialLocation:
                                        tab.branchIndex ==
                                        navigationShell.currentIndex,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BottomNavTabButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BottomNavTabButton({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final color = isSelected ? c.primary : c.textSecondary;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? c.primarySubtle : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isSelected ? activeIcon : icon,
                  size: 21.5,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11.2,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeWidgetSyncAndIntentHost extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  final Widget child;

  const _HomeWidgetSyncAndIntentHost({
    required this.navigationShell,
    required this.child,
  });

  @override
  State<_HomeWidgetSyncAndIntentHost> createState() =>
      _HomeWidgetSyncAndIntentHostState();
}

class _HomeWidgetSyncAndIntentHostState
    extends State<_HomeWidgetSyncAndIntentHost> {
  StreamSubscription<String>? _widgetActionSub;
  StreamSubscription<IncomingBankingPushPayload>? _fcmForegroundSub;
  StreamSubscription<IncomingBankingPushPayload>? _fcmDeepLinkSub;

  @override
  void initState() {
    super.initState();
    final bridge = sl<NativeHomeWidgetBridge>();
    final fcmService = sl<FcmBankingMessagingService>();
    _widgetActionSub = bridge.widgetActions.listen(_handleWidgetAction);
    _fcmForegroundSub = fcmService.foregroundNotifications.listen(
      _handleForegroundBankingPush,
    );
    _fcmDeepLinkSub = fcmService.deepLinkRequests.listen(
      _handleBankingPushDeepLink,
    );
    NativeAlarmSchedulerBridge.instance.setOnAlarmRingingListener(
      _handleRingingAlarm,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pending = await bridge.consumePendingWidgetAction();
      if (pending != null && mounted) {
        _handleWidgetAction(pending);
      }
      final pendingAlarm = await NativeAlarmSchedulerBridge.instance
          .consumeInitialAlarmPayload();
      if (pendingAlarm != null && mounted) {
        _handleRingingAlarm(pendingAlarm);
      }
      final coldStartPush = fcmService.consumePendingColdStartDeepLink();
      if (coldStartPush != null && mounted) {
        _handleBankingPushDeepLink(coldStartPush);
      }
    });
  }

  void _handleForegroundBankingPush(IncomingBankingPushPayload payload) {
    if (!mounted) return;
    LifeOsTopToast.show(
      context,
      '${payload.title}${payload.body.isNotEmpty ? " · ${payload.body.replaceAll("\n", " · ")}" : ""}',
      kind: payload.direction == 'credit'
          ? LifeOsToastKind.success
          : LifeOsToastKind.info,
    );
  }

  void _handleBankingPushDeepLink(IncomingBankingPushPayload payload) {
    if (!mounted) return;
    final txId = Uri.encodeQueryComponent(payload.transactionId);
    context.push('/auto-tx-review?txId=$txId');
  }

  void _handleRingingAlarm(Map<String, String> payload) {
    if (!mounted) return;
    final now = DateTime.now();
    final eventId = payload['eventId'] ?? '';
    final existing = context
        .read<CalendarBloc>()
        .state
        .events
        .where((e) => e.id == eventId)
        .firstOrNull;
    final ev =
        existing ??
        CalendarEventEntity(
          id: eventId.isEmpty ? 'alarm_ringing' : eventId,
          ownerId: 'self',
          ownerName: 'LifeOS',
          calendarId: 'primary',
          visibility: CalendarEventVisibility.privateEvent,
          title: payload['title'] ?? 'Nhắc lịch trình LifeOS',
          location: payload['subtitle'],
          startsAt: now,
          endsAt: now.add(const Duration(hours: 1)),
        );
    context.push('/event-alarm', extra: ev);
  }

  void _handleWidgetAction(String action) {
    if (!mounted) return;
    switch (action) {
      case NativeHomeWidgetBridge.actionVoiceCapture:
        showVoiceSmartCaptureSheet(context, autoStartListening: true);
      case NativeHomeWidgetBridge.actionVoiceSplit:
        showVoiceSmartCaptureSheet(
          context,
          autoStartListening: true,
          initialTranscript: 'Ăn lẩu bò 450 nghìn chia đều 3 người',
        );
      case NativeHomeWidgetBridge.actionOpenToday:
        widget.navigationShell.goBranch(0);
      case NativeHomeWidgetBridge.actionOpenFinance:
        widget.navigationShell.goBranch(1);
      case NativeHomeWidgetBridge.actionOpenFamily:
        widget.navigationShell.goBranch(3);
    }
  }

  void _syncAllHomeWidgets() {
    final dash = context.read<DashboardBloc>().state.data;
    final fam = context.read<FamilyBloc>().state.activeFamily;
    final autoConfirm =
        context
            .read<NotificationIngestionBloc>()
            .state
            .consent
            ?.autoConfirmSignals ??
        false;
    final runway = EmergencyRunwaySnapshot.compute(
      netLiquidMinor: dash.netWorthMinor,
      monthlyExpenseMinor: dash.monthlyExpenseMinor,
    );
    final usedPct = dash.dailySafeToSpendMinor > 0
        ? ((dash.todayExpenseMinor * 100) ~/ dash.dailySafeToSpendMinor).clamp(
            5,
            100,
          )
        : 15;

    sl<NativeHomeWidgetBridge>().syncWidgets(
      netWorth: VndAmount.format(dash.netWorthMinor),
      monthlyIncome: '+${VndAmount.format(dash.monthlyIncomeMinor)}',
      monthlyExpense: '-${VndAmount.format(dash.monthlyExpenseMinor)}',
      todayExpense: VndAmount.format(dash.todayExpenseMinor),
      safeDaily: VndAmount.format(dash.dailySafeToSpendMinor),
      wealthBadge: autoConfirm ? 'Auto-Ledger BẬT' : 'Auto-Sync',
      groupTitle: fam != null
          ? '${fam.name.toUpperCase()} · ${fam.members.length} THÀNH VIÊN'
          : 'HỘI NHÓM & GIA ĐÌNH · CHIA TIỀN NHANH',
      groupStatus: 'Nói câu chia ăn uống, việc nhà, điện nước',
      runwayLabel:
          'Quỹ dự phòng: ${runway.monthsOfRunway.toStringAsFixed(1)} tháng · ${runway.statusBadge}',
      dailyUsedPct: usedPct,
    );
  }

  @override
  void dispose() {
    NativeAlarmSchedulerBridge.instance.setOnAlarmRingingListener(null);
    _widgetActionSub?.cancel();
    _fcmForegroundSub?.cancel();
    _fcmDeepLinkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<DashboardBloc, DashboardState>(
          listenWhen: (p, c) => p.data != c.data,
          listener: (_, __) => _syncAllHomeWidgets(),
        ),
        BlocListener<FamilyBloc, FamilyState>(
          listenWhen: (p, c) => p.activeFamily != c.activeFamily,
          listener: (_, __) => _syncAllHomeWidgets(),
        ),
      ],
      child: widget.child,
    );
  }
}
