import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_assets.dart';
import '../core/di/dependency_injection.dart';
import '../core/navigation/feature_registry.dart';
import '../core/services/fcm_banking_messaging_service.dart';
import '../core/services/native_alarm_scheduler_bridge.dart';
import '../core/services/native_home_widget_bridge.dart';
import '../core/services/native_permissions_service.dart';
import '../core/utils/omni_action_executor.dart';
import '../core/utils/smart_omni_intent_parser.dart';
import '../core/utils/smart_quick_entry_parser.dart';
import '../core/utils/user_behavior_prefs.dart';
import '../core/utils/vnd_amount.dart';
import '../core/widgets/lifeos_design_system.dart';
import '../core/widgets/voice_smart_capture_sheet.dart';
import '../features/authentication/presentation/bloc/auth_bloc.dart';
import '../features/authentication/presentation/bloc/auth_state.dart';
import '../features/authentication/presentation/pages/account_profile_page.dart';
import '../features/authentication/presentation/pages/auth_pages.dart';
import '../features/authentication/presentation/pages/splash_page.dart';
import '../features/automation/presentation/bloc/automation_bloc.dart';
import '../features/automation/presentation/pages/automation_studio_page.dart';
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
import '../features/dashboard/presentation/pages/life_timeline_page.dart';
import '../features/dashboard/presentation/pages/today_page.dart';
import '../features/documents/presentation/bloc/document_vault_bloc.dart';
import '../features/documents/presentation/pages/family_documents_page.dart';
import '../features/family/presentation/bloc/family_bloc.dart';
import '../features/family/presentation/pages/family_funds_page.dart';
import '../features/family/presentation/pages/family_page.dart';
import '../features/financial_ai/domain/entities/financial_ai_entities.dart';
import '../features/financial_ai/presentation/bloc/financial_ai_bloc.dart';
import '../features/financial_ai/presentation/bloc/gemini_copilot_bloc.dart';
import '../features/financial_ai/presentation/pages/financial_ai_assistant_page.dart';
import '../features/financial_ai/presentation/pages/financial_ai_settings_page.dart';
import '../features/motion_gallery/presentation/pages/motion_gallery_page.dart';
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
import '../features/transactions/presentation/bloc/transaction_state.dart';
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

Page<void> _motionPage(
  GoRouterState state,
  WidgetBuilder builder, {
  bool fadeThrough = false,
}) {
  final child = Builder(builder: builder);
  return fadeThrough
      ? LifeOsPageTransitions.fadeThrough<void>(state: state, child: child)
      : LifeOsPageTransitions.sharedAxis<void>(state: state, child: child);
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
      GoRoute(
        path: '/splash',
        pageBuilder: (_, state) =>
            _motionPage(state, (_) => const SplashPage(), fadeThrough: true),
      ),
      GoRoute(
        path: '/welcome',
        pageBuilder: (_, state) =>
            _motionPage(state, (_) => const WelcomePage()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) =>
            _motionPage(state, (_) => const LoginPage(), fadeThrough: true),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (_, state) =>
            _motionPage(state, (_) => const RegisterPage()),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (_, state) => _motionPage(
          state,
          (_) => ForgotPasswordPage(
            initialEmail: state.extra is String ? state.extra as String : null,
          ),
        ),
      ),
      GoRoute(
        path: '/verify-otp',
        pageBuilder: (_, state) => _motionPage(
          state,
          (_) => VerifyOtpPage(
            email: state.extra is String ? state.extra as String : null,
          ),
        ),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (_, state) =>
            _motionPage(state, (_) => const ResetPasswordPage()),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, state) =>
            _motionPage(state, (_) => const OnboardingPrivacyPage()),
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
                builder: (_, state) => PlanningPage(
                  initialViewMode: state.uri.queryParameters['view'],
                  initialTabIndex: FeatureRegistry.normalizePlanningTabIndex(
                    state.uri.queryParameters['tab'],
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/family', builder: (_, __) => const FamilyPage()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/menu',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const SuperAppDirectoryPage(isEmbeddedShellTab: false),
          );
        }),
      ),
      GoRoute(
        path: '/assets',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const AssetsPage(),
          );
        }),
      ),
      GoRoute(
        path: '/account-profile',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return const AccountProfilePage();
        }),
      ),
      GoRoute(
        path: '/notifications-privacy',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const NotificationsPrivacyPage(),
          );
        }),
      ),
      GoRoute(
        path: '/home-widgets',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const HomeWidgetsStudioPage(),
          );
        }),
      ),
      GoRoute(
        path: '/event-detail',
        pageBuilder: (_, state) => _motionPage(state, (context) {
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
        }),
      ),
      GoRoute(
        path: '/event-alarm',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: EventAlarmPage(
              event: state.extra is CalendarEventEntity
                  ? state.extra as CalendarEventEntity
                  : null,
            ),
          );
        }, fadeThrough: true),
      ),
      GoRoute(
        path: '/tasks-board',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const TasksBoardPage(),
          );
        }),
      ),
      GoRoute(
        path: '/auto-tx-review',
        pageBuilder: (_, state) => _motionPage(state, (context) {
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
        }),
      ),
      GoRoute(
        path: '/finance-report',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const FinanceReportPage(),
          );
        }),
      ),
      GoRoute(
        path: '/family-funds',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const FamilyFundsPage(),
          );
        }),
      ),
      GoRoute(
        path: '/family-documents',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const FamilyDocumentsPage(),
          );
        }),
      ),
      GoRoute(
        path: '/activity-notifications',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const ActivityNotificationsPage(),
          );
        }),
      ),
      GoRoute(
        path: '/settings-hub',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const SettingsHubPage(),
          );
        }),
      ),
      GoRoute(
        path: '/pro-utilities',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const ProUtilitiesHubPage(),
          );
        }),
      ),
      GoRoute(
        path: '/subscriptions-warranty',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const SubscriptionsWarrantyPage(),
          );
        }),
      ),
      GoRoute(
        path: '/habits-focus',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const HabitsFocusPage(),
          );
        }),
      ),
      GoRoute(
        path: '/social-ledger-travel',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const SocialLedgerTravelPage(),
          );
        }),
      ),
      GoRoute(
        path: '/wealth-tools',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: WealthToolsPage(
              initialTab: state.uri.queryParameters['tab'],
            ),
          );
        }),
      ),
      GoRoute(
        path: '/super-app-hub',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const SuperAppDirectoryPage(),
          );
        }),
      ),
      GoRoute(
        path: '/health-hub',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: HealthMedicalHubPage(
              initialTab: state.uri.queryParameters['tab'],
            ),
          );
        }),
      ),
      GoRoute(
        path: '/kitchen-groceries',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const KitchenGroceriesPage(),
          );
        }),
      ),
      GoRoute(
        path: '/home-living',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const HomeLivingUtilitiesPage(),
          );
        }),
      ),
      GoRoute(
        path: '/smart-notes-hub',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: SmartNotesSalaryPage(
              initialTab: state.uri.queryParameters['tab'],
            ),
          );
        }),
      ),
      GoRoute(
        path: '/financial-ai',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          String? initialText;
          var initialSource = FinancialInputSource.manualText;
          final extra = state.extra;
          if (extra is String) {
            initialText = extra;
          } else if (extra is Map<String, dynamic>) {
            final rawText = extra['initialText'];
            if (rawText is String) initialText = rawText;
            final rawSource = extra['initialSource'];
            if (rawSource is FinancialInputSource) {
              initialSource = rawSource;
            }
          }
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: FinancialAiAssistantPage(
              initialText: initialText,
              initialSource: initialSource,
            ),
          );
        }),
      ),
      GoRoute(
        path: '/financial-ai-settings',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const FinancialAiSettingsPage(),
          );
        }),
      ),
      GoRoute(
        path: '/motion-gallery',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const MotionGalleryPage(),
          );
        }),
      ),
      GoRoute(
        path: '/automation-studio',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const AutomationStudioPage(),
          );
        }),
      ),
      GoRoute(
        path: '/life-timeline',
        pageBuilder: (_, state) => _motionPage(state, (context) {
          final user = context.read<AuthBloc>().state.user;
          if (user == null) return const LoginPage();
          return _ScopedAuthenticatedProviders(
            userId: user.id,
            familyId: user.activeFamilyId,
            child: const LifeTimelinePage(),
          );
        }),
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
        BlocProvider<FinancialAiBloc>(
          create: (_) =>
              sl<FinancialAiBloc>()..add(FinancialAiInitialized(userId)),
        ),
        BlocProvider<GeminiCopilotBloc>(
          create: (_) =>
              sl<GeminiCopilotBloc>()..add(const GeminiCopilotInitialized()),
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
        BlocProvider<AutomationBloc>(
          create: (_) => sl<AutomationBloc>()..add(AutomationStarted(userId)),
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
      String bananaAsset,
      String label,
    })
  >
  _tabs = [
    (
      branchIndex: 0,
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      bananaAsset: AppAssets.icNavToday,
      label: 'Hôm nay',
    ),
    (
      branchIndex: 1,
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      bananaAsset: AppAssets.icNavFinance,
      label: 'Tài chính',
    ),
    (
      branchIndex: 2,
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
      bananaAsset: AppAssets.icNavCalendar,
      label: 'Lịch & Việc',
    ),
    (
      branchIndex: 3,
      icon: Icons.groups_outlined,
      activeIcon: Icons.groups_rounded,
      bananaAsset: AppAssets.icNavFamily,
      label: 'Gia đình',
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
                            Tooltip(
                              message: 'Bảng tính năng LifeOS',
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  key: const Key(
                                    'open_logo_side_drawer_rail_button',
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () =>
                                      showLifeOsLogoSideDrawer(context),
                                  child: const LifeOsLeafMark(
                                    size: 38,
                                    borderRadius: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            IconButton.filled(
                              key: const Key('lifeos_center_quick_add_fab'),
                              tooltip: 'Thêm nhanh',
                              onPressed: () =>
                                  showLifeOsQuickCreateHub(context),
                              icon: const Icon(Icons.add_rounded),
                            ),
                            const SizedBox(height: 6),
                            IconButton.outlined(
                              key: const Key('open_menu_directory_button'),
                              tooltip: 'Menu',
                              onPressed: () => context.push('/menu'),
                              icon: const Icon(Icons.grid_view_rounded),
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
                              icon: BananaGlassIcon(
                                assetPath: t.bananaAsset,
                                fallbackIcon: t.icon,
                                size: 28,
                                borderRadius: 9,
                              ),
                              selectedIcon: BananaGlassIcon(
                                assetPath: t.bananaAsset,
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

            return Scaffold(
              extendBody: true,
              body: Stack(
                children: [
                  _SlidingShellViewport(
                    currentIndex: navigationShell.currentIndex,
                    child: navigationShell,
                  ),
                  Positioned(
                    key: const Key('shell_left_edge_drawer_swipe_zone'),
                    left: 0,
                    top: 0,
                    bottom: 68,
                    width: 14,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: (details) {
                        if ((details.primaryVelocity ?? 0) > 260) {
                          showLifeOsLogoSideDrawer(context);
                        }
                      },
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: RepaintBoundary(
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                    child: LiquidGlassSlidingDock(
                      dockKey: const Key('lifeos_liquid_glass_bottom_dock'),
                      selectedIndex: navigationShell.currentIndex.clamp(0, 3),
                      onDestinationSelected: (branchIdx) =>
                          navigationShell.goBranch(
                            branchIdx,
                            initialLocation:
                                branchIdx == navigationShell.currentIndex,
                          ),
                      jewelSlotWidth: 58,
                      centerJewel: LiquidGlassJewelButton(
                        buttonKey: const Key('lifeos_center_quick_add_fab'),
                        tooltip: 'Thêm nhanh',
                        size: 48,
                        onTap: () => showLifeOsQuickCreateHub(context),
                      ),
                      items: _tabs
                          .map(
                            (t) => LiquidGlassDockItem(
                              branchIndex: t.branchIndex,
                              label: t.label,
                              iconBuilder: (ctx, isSelected, color) =>
                                  BananaGlassIcon(
                                    assetPath: t.bananaAsset,
                                    fallbackIcon: isSelected
                                        ? t.activeIcon
                                        : t.icon,
                                    fallbackColor: color,
                                    size: isSelected ? 26 : 24,
                                    borderRadius: 8,
                                    isSelected: isSelected,
                                  ),
                            ),
                          )
                          .toList(),
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

/// Synchronizes subtle directional horizontal glide with the sliding bottom dock
/// without ever unmounting [StatefulNavigationShell] or losing scroll/BLoC state.
class _SlidingShellViewport extends StatefulWidget {
  final int currentIndex;
  final Widget child;

  const _SlidingShellViewport({
    required this.currentIndex,
    required this.child,
  });

  @override
  State<_SlidingShellViewport> createState() => _SlidingShellViewportState();
}

class _SlidingShellViewportState extends State<_SlidingShellViewport>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;
  LifeOsMotionPreferences _motion = const LifeOsMotionPreferences();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: LifeOsMotionTokens.standard,
      value: 1.0,
    );
    _slideAnim = const AlwaysStoppedAnimation<Offset>(Offset.zero);
    _fadeAnim = const AlwaysStoppedAnimation<double>(1.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = LifeOsMotionScope.of(context);
  }

  @override
  void didUpdateWidget(covariant _SlidingShellViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      if (_motion.isMotionOff || !TickerMode.valuesOf(context).enabled) {
        _controller.stop();
        _slideAnim = const AlwaysStoppedAnimation<Offset>(Offset.zero);
        _fadeAnim = const AlwaysStoppedAnimation<double>(1.0);
        _controller.value = 1.0;
        return;
      }

      _controller.duration = _motion.resolveDuration(
        LifeOsMotionTokens.standard,
      );
      final curve = CurvedAnimation(
        parent: _controller,
        curve: LifeOsMotionTokens.standardCurve,
      );

      if (_motion.isReducedMotion) {
        _slideAnim = const AlwaysStoppedAnimation<Offset>(Offset.zero);
        _fadeAnim = Tween<double>(begin: 0.94, end: 1.0).animate(curve);
      } else {
        final dir = widget.currentIndex > oldWidget.currentIndex ? 1.0 : -1.0;
        // Blend smoothly from any mid-flight residual offset so rapid 0->2->1->3 taps never snap
        final residualDx = _slideAnim.value.dx;
        final startDx =
            (residualDx * 0.35 +
                    dir * LifeOsMotionTokens.shellBranchSlideFraction)
                .clamp(-0.032, 0.032);
        _slideAnim = Tween<Offset>(
          begin: Offset(startDx, 0),
          end: Offset.zero,
        ).animate(curve);
        _fadeAnim = Tween<double>(begin: 0.95, end: 1.0).animate(curve);
      }
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(position: _slideAnim, child: widget.child),
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
    extends State<_HomeWidgetSyncAndIntentHost>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _widgetActionSub;
  StreamSubscription<void>? _bgWidgetCmdSub;
  StreamSubscription<IncomingBankingPushPayload>? _fcmForegroundSub;
  StreamSubscription<IncomingBankingPushPayload>? _fcmDeepLinkSub;
  bool _isDrainingWidgetCommands = false;
  static final Map<String, String> _syncedWidgetCmdToTxId = <String, String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final bridge = sl<NativeHomeWidgetBridge>();
    final fcmService = sl<FcmBankingMessagingService>();
    _widgetActionSub = bridge.widgetActions.listen(_handleWidgetAction);
    _bgWidgetCmdSub = bridge.backgroundCommandSignals.listen(
      (_) => _drainHomeScreenWidgetCommands(),
    );
    _fcmForegroundSub = fcmService.foregroundNotifications.listen(
      _handleForegroundBankingPush,
    );
    _fcmDeepLinkSub = fcmService.deepLinkRequests.listen(
      _handleBankingPushDeepLink,
    );
    NativeAlarmSchedulerBridge.instance.setOnAlarmRingingListener(
      _handleRingingAlarm,
    );
    NativeAlarmSchedulerBridge.instance.setOnBackgroundHealthActionListener(
      _drainBackgroundHealthActions,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _drainBackgroundHealthActions();
      await _drainHomeScreenWidgetCommands();
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
      await _maybePromptFirstRunPermissionsPopup();
    });
  }

  Future<void> _maybePromptFirstRunPermissionsPopup() async {
    if (!mounted) return;
    final dismissed = await UserBehaviorPrefs.hasDismissedPermissionsPopup();
    if (dismissed || !mounted) return;
    final snap = await NativePermissionsService.instance.checkAll();
    if (!mounted || snap.isAllEssentialGranted) return;
    await showLifeOsPermissionsPopup(context, initialSnapshot: snap);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCalendarMonthRollover();
      _drainBackgroundHealthActions();
      _drainHomeScreenWidgetCommands();
    }
  }

  void _checkCalendarMonthRollover() {
    if (!mounted) return;
    final user = context.read<AuthBloc>().state.user;
    if (user == null || user.id.isEmpty) return;
    final currentMonthKey = TransactionListBloc.currentMonthKey();
    final txListBloc = context.read<TransactionListBloc>();
    if (txListBloc.state.monthKey != currentMonthKey) {
      txListBloc.add(
        TransactionsSubscriptionRequested(
          userId: user.id,
          monthKey: currentMonthKey,
        ),
      );
      context.read<BudgetBloc>().add(
        BudgetsSubscriptionRequested(
          userId: user.id,
          monthKey: currentMonthKey,
          familyId: user.activeFamilyId,
        ),
      );
    }
  }

  void _drainBackgroundHealthActions() {
    if (!mounted) return;
    final uid = context.read<AuthBloc>().state.user?.id;
    if (uid != null && uid.isNotEmpty) {
      context.read<DailyLifeBloc>().add(
        BackgroundHealthActionsSynced(userId: uid),
      );
    }
  }

  Future<void> _drainHomeScreenWidgetCommands() async {
    if (!mounted || _isDrainingWidgetCommands) return;
    _isDrainingWidgetCommands = true;
    try {
      final commands = await sl<NativeHomeWidgetBridge>()
          .drainQueuedWidgetCommands();
      if (!mounted || commands.isEmpty) return;

      final user = context.read<AuthBloc>().state.user;
      if (user == null) return;

      final txActionBloc = context.read<TransactionActionBloc>();
      final familyBloc = context.read<FamilyBloc>();
      final wallets = context.read<TransactionListBloc>().state.wallets;
      final walletId = UserBehaviorPrefs.resolvePreferredWalletId(
        wallets.map((w) => w.id),
      );

      var appliedCount = 0;
      for (final cmd in commands) {
        if (!mounted) break;
        if (cmd.kind == 'undo') {
          final txId =
              _syncedWidgetCmdToTxId[cmd.targetCommandId] ??
              cmd.targetCommandId;
          if (txId.isNotEmpty) {
            txActionBloc.add(
              TransactionReverseRequested(
                userId: user.id,
                transactionId: txId,
                reason: 'Hoàn tác từ Widget màn hình chính',
              ),
            );
            appliedCount++;
          }
          continue;
        }

        if (cmd.kind == 'expense' || cmd.kind == 'income') {
          final parsed = SmartQuickEntryParser.tryParse(cmd.commandText);
          final amount = cmd.amountMinor > 0
              ? cmd.amountMinor
              : (parsed?.amountMinor ?? 0);
          if (amount <= 0) continue;
          final opId = cmd.id.isNotEmpty
              ? cmd.id
              : 'widget_tx_${DateTime.now().microsecondsSinceEpoch}';
          final txKind = cmd.kind == 'income'
              ? TransactionKind.income
              : TransactionKind.expense;
          final catId =
              parsed?.categoryId ??
              (txKind == TransactionKind.income
                  ? 'cat_other_inc'
                  : 'cat_other_exp');
          final catName =
              parsed?.categoryName ??
              (txKind == TransactionKind.income
                  ? 'Thu nhập khác'
                  : 'Chi tiêu khác');
          final title = cmd.label.trim().isNotEmpty
              ? cmd.label.trim()
              : (parsed?.merchant ?? 'Ghi từ Widget');

          final outcome = await txActionBloc.submitAndAwaitCreate(
            TransactionCreateSubmitted(
              operationId: opId,
              userId: user.id,
              walletId: walletId,
              categoryId: catId,
              categoryName: catName,
              kind: txKind,
              amountMinor: amount,
              merchant: title,
              note: 'Ghi trực tiếp ngoài Widget màn hình chính',
              occurredAt: cmd.createdAtEpochMs > 0
                  ? DateTime.fromMillisecondsSinceEpoch(cmd.createdAtEpochMs)
                  : DateTime.now(),
            ),
          );
          final createdTx = outcome.lastCreatedTransaction;
          if (outcome.status == ActionStatus.success && createdTx != null) {
            _syncedWidgetCmdToTxId[cmd.id] = createdTx.id;
            await UserBehaviorPrefs.recordHabitExecution(
              label: '$title ${(amount / 1000).round()}k',
              commandText: '$title ${(amount / 1000).round()}k',
              categoryName: catName,
              amountMinor: amount,
            );
            appliedCount++;
          }
          continue;
        }

        if (cmd.kind == 'group_split' && cmd.amountMinor > 0) {
          final ok = await OmniActionExecutor.executeDraft(
            toastContext: context,
            draft: OmniActionDraft(
              id: cmd.id.isNotEmpty ? cmd.id : 'widget_split_$appliedCount',
              kind: OmniActionKind.groupSplit,
              title: cmd.label.trim().isNotEmpty
                  ? cmd.label.trim()
                  : 'Khoản chia chung',
              amountMinor: cmd.amountMinor,
              participantCount: cmd.memberCount.clamp(2, 20),
              originLabel: 'Widget màn hình chính',
            ),
            user: user,
            walletId: walletId,
            familyBloc: familyBloc,
            showSuccessToast: false,
          );
          if (ok) appliedCount++;
          continue;
        }

        if (cmd.commandText.trim().isNotEmpty) {
          final calBloc = context.read<CalendarBloc>();
          final taskBloc = context.read<TaskBloc>();
          final dailyBloc = context.read<DailyLifeBloc>();
          final drafts = SmartOmniIntentParser.parseMulti(cmd.commandText);
          for (final draft in drafts) {
            if (!mounted) break;
            final ok = await OmniActionExecutor.executeDraft(
              toastContext: context,
              draft: draft,
              user: user,
              walletId: walletId,
              txActionBloc: txActionBloc,
              calBloc: calBloc,
              taskBloc: taskBloc,
              familyBloc: familyBloc,
              dailyBloc: dailyBloc,
              showSuccessToast: false,
            );
            if (ok) appliedCount++;
          }
        }
      }

      if (appliedCount > 0 && mounted) {
        LifeOsTopToast.show(
          context,
          'Đã đồng bộ $appliedCount thao tác từ Widget ngoài màn hình chính.',
          kind: LifeOsToastKind.success,
        );
      }
    } finally {
      _isDrainingWidgetCommands = false;
    }
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
    if (eventId.startsWith('water_')) {
      final user = context.read<AuthBloc>().state.user;
      final hyd = context.read<DailyLifeBloc>().state.snapshot.hydration;
      final cup = hyd.preferredCupMl;
      context.push('/health-hub?tab=water');
      LifeOsTopToast.show(
        context,
        payload['title'] ?? 'Đến giờ uống nước rồi!',
        kind: LifeOsToastKind.info,
        actionLabel: user != null ? '+${cup}ml' : null,
        onAction: user == null
            ? null
            : () {
                context.read<DailyLifeBloc>().add(
                  WaterIntakeLogged(
                    userId: user.id,
                    deltaMl: cup,
                    targetWaterMl: hyd.targetWaterMl,
                  ),
                );
              },
        duration: const Duration(milliseconds: 5000),
      );
      return;
    }
    if (eventId.startsWith('med_')) {
      context.push('/health-hub?tab=meds');
      LifeOsTopToast.show(
        context,
        payload['title'] ?? 'Đến giờ uống thuốc!',
        kind: LifeOsToastKind.warning,
        duration: const Duration(milliseconds: 4500),
      );
      return;
    }
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
          title: payload['title'] ?? 'Báo thức LifeOS',
          location: payload['subtitle'],
          startsAt: now,
          endsAt: now.add(const Duration(hours: 1)),
          reminderMinutesBefore: 0,
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
      wealthBadge: autoConfirm ? 'Auto-Ledger BẬT' : 'Đổi góc nhìn',
      groupTitle: fam != null
          ? '${fam.name} · ${fam.members.length} thành viên'
          : 'Tổ ấm & Hội nhóm',
      groupStatus: 'Chọn số người rồi chạm mức chia nhanh bên dưới',
      runwayLabel:
          'Quỹ dự phòng: ${runway.monthsOfRunway.toStringAsFixed(1)} tháng · ${runway.statusBadge}',
      dailyUsedPct: usedPct,
      netWorthMinor: dash.netWorthMinor,
      monthlyIncomeMinor: dash.monthlyIncomeMinor,
      monthlyExpenseMinor: dash.monthlyExpenseMinor,
      todayExpenseMinor: dash.todayExpenseMinor,
      safeDailyMinor: dash.dailySafeToSpendMinor,
      groupMemberCount: fam != null && fam.members.length >= 2
          ? fam.members.length
          : null,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NativeAlarmSchedulerBridge.instance.setOnAlarmRingingListener(null);
    NativeAlarmSchedulerBridge.instance.setOnBackgroundHealthActionListener(
      null,
    );
    _widgetActionSub?.cancel();
    _bgWidgetCmdSub?.cancel();
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
