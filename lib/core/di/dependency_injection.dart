import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;

import '../../app/theme/theme_bloc.dart';
import '../../features/app_update/data/datasources/app_update_remote_datasource.dart';
import '../../features/app_update/data/repositories/app_update_repository_impl.dart';
import '../../features/app_update/domain/repositories/app_update_repository.dart';
import '../../features/app_update/domain/usecases/app_update_usecases.dart';
import '../../features/app_update/presentation/bloc/app_update_bloc.dart';
import '../../features/authentication/data/datasources/firebase_auth_remote_datasource.dart';
import '../../features/authentication/data/repositories/auth_repository_impl.dart';
import '../../features/authentication/domain/repositories/auth_repository.dart';
import '../../features/authentication/domain/usecases/auth_usecases.dart';
import '../../features/authentication/presentation/bloc/auth_bloc.dart';
import '../../features/budgets/data/repositories/budget_repository_impl.dart';
import '../../features/budgets/domain/repositories/budget_repository.dart';
import '../../features/budgets/domain/usecases/budget_usecases.dart';
import '../../features/budgets/presentation/bloc/budget_bloc.dart';
import '../../features/calendar/data/datasources/google_calendar_api_datasource.dart';
import '../../features/calendar/data/repositories/calendar_repository_impl.dart';
import '../../features/calendar/domain/repositories/calendar_repository.dart';
import '../../features/calendar/presentation/bloc/calendar_bloc.dart';
import '../../features/dashboard/data/repositories/dashboard_repository_impl.dart';
import '../../features/dashboard/domain/repositories/dashboard_repository.dart';
import '../../features/dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../features/family/data/repositories/family_repository_impl.dart';
import '../../features/family/domain/repositories/family_repository.dart';
import '../../features/family/domain/usecases/family_usecases.dart';
import '../../features/family/presentation/bloc/family_bloc.dart';
import '../../features/notifications/data/datasources/sepay_api_datasource.dart';
import '../../features/notifications/data/repositories/notifications_repository_impl.dart';
import '../../features/notifications/domain/repositories/notifications_repository.dart';
import '../../features/notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../../features/tasks/data/repositories/task_repository_impl.dart';
import '../../features/tasks/domain/repositories/task_repository.dart';
import '../../features/tasks/presentation/bloc/task_bloc.dart';
import '../../features/transactions/data/datasources/transaction_remote_datasource.dart';
import '../../features/transactions/data/repositories/transaction_repository_impl.dart';
import '../../features/transactions/domain/repositories/transaction_repository.dart';
import '../../features/transactions/domain/usecases/transaction_usecases.dart';
import '../../features/transactions/presentation/bloc/transaction_bloc.dart';
import '../../features/vehicles/data/repositories/vehicle_repository_impl.dart';
import '../../features/vehicles/domain/repositories/vehicle_repository.dart';
import '../../features/vehicles/presentation/bloc/vehicle_bloc.dart';
import '../services/android_notification_bridge.dart';
import '../services/file_storage_service.dart';
import '../services/native_app_updater_bridge.dart';

final GetIt sl = GetIt.instance;

Future<void> configureDependencies({
  FirebaseAuth? authOverride,
  FirebaseFirestore? firestoreOverride,
  AndroidNotificationBridge? bridgeOverride,
  NativeAppUpdaterBridge? updaterBridgeOverride,
  GoogleAuthHandler? googleAuthOverride,
  GoogleCalendarTokenProvider? googleCalendarTokenOverride,
  http.Client? httpClientOverride,
}) async {
  await sl.reset();

  // 1. Infrastructure Singletons
  sl.registerSingleton<FirebaseAuth>(authOverride ?? FirebaseAuth.instance);
  sl.registerSingleton<FirebaseFirestore>(firestoreOverride ?? FirebaseFirestore.instance);
  sl.registerSingleton<AndroidNotificationBridge>(
    bridgeOverride ?? AndroidNotificationBridge(),
  );
  sl.registerSingleton<NativeAppUpdaterBridge>(
    updaterBridgeOverride ?? const NativeAppUpdaterBridge(),
  );
  sl.registerLazySingleton<FileStorageService>(
    () => const SparkSafeFileStorageService(),
  );

  // 2. Remote Data Sources
  sl.registerLazySingleton<AppUpdateRemoteDataSource>(
    () => AppUpdateRemoteDataSource(
      firestore: sl<FirebaseFirestore>(),
      updaterBridge: sl<NativeAppUpdaterBridge>(),
      httpClient: httpClientOverride,
    ),
  );
  sl.registerLazySingleton<FirebaseAuthRemoteDataSource>(
    () => FirebaseAuthRemoteDataSource(
      firebaseAuth: sl<FirebaseAuth>(),
      firestore: sl<FirebaseFirestore>(),
      googleAuthOverride: googleAuthOverride,
    ),
  );
  sl.registerLazySingleton<TransactionRemoteDataSource>(
    () => TransactionRemoteDataSource(sl<FirebaseFirestore>()),
  );
  sl.registerLazySingleton<BudgetRemoteDataSource>(
    () => BudgetRemoteDataSource(sl<FirebaseFirestore>()),
  );
  sl.registerLazySingleton<FamilyRemoteDataSource>(
    () => FamilyRemoteDataSource(sl<FirebaseFirestore>()),
  );
  sl.registerLazySingleton<GoogleCalendarApiDataSource>(
    () => GoogleCalendarApiDataSource(
      firebaseAuth: sl<FirebaseAuth>(),
      httpClient: httpClientOverride,
      tokenProviderOverride: googleCalendarTokenOverride,
    ),
  );
  sl.registerLazySingleton<CalendarRemoteDataSource>(
    () => CalendarRemoteDataSource(
      sl<FirebaseFirestore>(),
      googleApi: sl<GoogleCalendarApiDataSource>(),
    ),
  );
  sl.registerLazySingleton<TaskRemoteDataSource>(
    () => TaskRemoteDataSource(sl<FirebaseFirestore>()),
  );
  sl.registerLazySingleton<VehicleRemoteDataSource>(
    () => VehicleRemoteDataSource(sl<FirebaseFirestore>()),
  );
  sl.registerLazySingleton<SePayApiDataSource>(
    () => SePayApiDataSource(httpClient: httpClientOverride),
  );
  sl.registerLazySingleton<NotificationsRemoteDataSource>(
    () => NotificationsRemoteDataSource(
      firestore: sl<FirebaseFirestore>(),
      firebaseAuth: sl<FirebaseAuth>(),
      bridge: sl<AndroidNotificationBridge>(),
      sePayApi: sl<SePayApiDataSource>(),
    ),
  );

  // 3. Domain Repository Implementations
  sl.registerLazySingleton<AppUpdateRepository>(
    () => AppUpdateRepositoryImpl(sl<AppUpdateRemoteDataSource>()),
  );
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(sl<FirebaseAuthRemoteDataSource>()),
  );
  sl.registerLazySingleton<TransactionRepository>(
    () => TransactionRepositoryImpl(sl<TransactionRemoteDataSource>()),
  );
  sl.registerLazySingleton<BudgetRepository>(
    () => BudgetRepositoryImpl(sl<BudgetRemoteDataSource>()),
  );
  sl.registerLazySingleton<FamilyRepository>(
    () => FamilyRepositoryImpl(sl<FamilyRemoteDataSource>()),
  );
  sl.registerLazySingleton<CalendarRepository>(
    () => CalendarRepositoryImpl(sl<CalendarRemoteDataSource>()),
  );
  sl.registerLazySingleton<TaskRepository>(
    () => TaskRepositoryImpl(sl<TaskRemoteDataSource>()),
  );
  sl.registerLazySingleton<VehicleRepository>(
    () => VehicleRepositoryImpl(sl<VehicleRemoteDataSource>()),
  );
  sl.registerLazySingleton<NotificationsRepository>(
    () => NotificationsRepositoryImpl(sl<NotificationsRemoteDataSource>()),
  );
  sl.registerLazySingleton<DashboardRepository>(
    () => DashboardRepositoryImpl(
      transactionRepo: sl<TransactionRepository>(),
      taskRepo: sl<TaskRepository>(),
      calendarRepo: sl<CalendarRepository>(),
      vehicleRepo: sl<VehicleRepository>(),
    ),
  );

  // 4. Use Cases
  sl.registerLazySingleton(() => CheckForAppUpdateUseCase(sl<AppUpdateRepository>()));
  sl.registerLazySingleton(() => DownloadAndInstallUpdateUseCase(sl<AppUpdateRepository>()));
  sl.registerLazySingleton(() => OpenReleasePageUseCase(sl<AppUpdateRepository>()));

  sl.registerLazySingleton(() => WatchCurrentUserUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => SignInUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => SignUpUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => SignInWithGoogleUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => LinkGoogleAccountUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => SendPasswordResetUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => SendEmailVerificationUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => ReloadCurrentUserUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => UpdateUserProfileUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => ChangePasswordUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => CompleteOnboardingUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => UpdatePrivacySettingsUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => SignOutUseCase(sl<AuthRepository>()));

  sl.registerLazySingleton(() => CreateWalletUseCase(sl<TransactionRepository>()));
  sl.registerLazySingleton(() => CreateTransactionUseCase(sl<TransactionRepository>()));
  sl.registerLazySingleton(() => ReverseTransactionUseCase(sl<TransactionRepository>()));
  sl.registerLazySingleton(
    () => DecideProvisionalTransactionUseCase(sl<TransactionRepository>()),
  );

  sl.registerLazySingleton(() => UpsertBudgetUseCase(sl<BudgetRepository>()));
  sl.registerLazySingleton(() => CreateFundUseCase(sl<BudgetRepository>()));
  sl.registerLazySingleton(() => ContributeToFundUseCase(sl<BudgetRepository>()));
  sl.registerLazySingleton(() => RequestFundExpenseUseCase(sl<BudgetRepository>()));
  sl.registerLazySingleton(() => DecideFundExpenseUseCase(sl<BudgetRepository>()));

  sl.registerLazySingleton(() => CreateFamilyUseCase(sl<FamilyRepository>()));
  sl.registerLazySingleton(() => JoinFamilyByCodeUseCase(sl<FamilyRepository>()));
  sl.registerLazySingleton(() => CreateSharedBillSplitUseCase(sl<FamilyRepository>()));
  sl.registerLazySingleton(() => RecordDebtSettlementUseCase(sl<FamilyRepository>()));

  sl.registerLazySingleton(() => CreateManagedCalendarUseCase(sl<CalendarRepository>()));
  sl.registerLazySingleton(() => CreateCalendarEventUseCase(sl<CalendarRepository>()));
  sl.registerLazySingleton(() => UpdateCalendarEventUseCase(sl<CalendarRepository>()));
  sl.registerLazySingleton(() => SyncGoogleCalendarUseCase(sl<CalendarRepository>()));

  sl.registerLazySingleton(() => CreateTaskUseCase(sl<TaskRepository>()));
  sl.registerLazySingleton(() => RespondToTaskUseCase(sl<TaskRepository>()));

  sl.registerLazySingleton(() => UpdateOdometerUseCase(sl<VehicleRepository>()));

  // 5. BLoC Factories (Scoped by presentation lifecycle — NEVER global business singletons)
  sl.registerFactory<ThemeBloc>(ThemeBloc.new);
  sl.registerFactory<AppUpdateBloc>(
    () => AppUpdateBloc(
      checkForUpdate: sl<CheckForAppUpdateUseCase>(),
      downloadAndInstall: sl<DownloadAndInstallUpdateUseCase>(),
      openReleasePage: sl<OpenReleasePageUseCase>(),
    ),
  );
  sl.registerFactory<AuthBloc>(
    () => AuthBloc(
      watchCurrentUser: sl<WatchCurrentUserUseCase>(),
      signIn: sl<SignInUseCase>(),
      signUp: sl<SignUpUseCase>(),
      signInWithGoogle: sl<SignInWithGoogleUseCase>(),
      linkGoogleAccount: sl<LinkGoogleAccountUseCase>(),
      sendPasswordReset: sl<SendPasswordResetUseCase>(),
      sendEmailVerification: sl<SendEmailVerificationUseCase>(),
      reloadCurrentUser: sl<ReloadCurrentUserUseCase>(),
      updateUserProfile: sl<UpdateUserProfileUseCase>(),
      changePassword: sl<ChangePasswordUseCase>(),
      completeOnboarding: sl<CompleteOnboardingUseCase>(),
      updatePrivacySettings: sl<UpdatePrivacySettingsUseCase>(),
      signOut: sl<SignOutUseCase>(),
    ),
  );
  sl.registerFactory<DashboardBloc>(
    () => DashboardBloc(repository: sl<DashboardRepository>()),
  );
  sl.registerFactory<TransactionListBloc>(
    () => TransactionListBloc(repository: sl<TransactionRepository>()),
  );
  sl.registerFactory<TransactionActionBloc>(
    () => TransactionActionBloc(
      createWallet: sl<CreateWalletUseCase>(),
      createTransaction: sl<CreateTransactionUseCase>(),
      reverseTransaction: sl<ReverseTransactionUseCase>(),
      decideProvisional: sl<DecideProvisionalTransactionUseCase>(),
    ),
  );
  sl.registerFactory<BudgetBloc>(
    () => BudgetBloc(
      repository: sl<BudgetRepository>(),
      upsertBudget: sl<UpsertBudgetUseCase>(),
      createFund: sl<CreateFundUseCase>(),
      contributeToFund: sl<ContributeToFundUseCase>(),
      requestFundExpense: sl<RequestFundExpenseUseCase>(),
      decideFundExpense: sl<DecideFundExpenseUseCase>(),
    ),
  );
  sl.registerFactory<FamilyBloc>(
    () => FamilyBloc(
      repository: sl<FamilyRepository>(),
      createFamily: sl<CreateFamilyUseCase>(),
      joinFamily: sl<JoinFamilyByCodeUseCase>(),
      createSharedBillSplit: sl<CreateSharedBillSplitUseCase>(),
      recordDebtSettlement: sl<RecordDebtSettlementUseCase>(),
    ),
  );
  sl.registerFactory<CalendarBloc>(
    () => CalendarBloc(
      repository: sl<CalendarRepository>(),
      createCalendar: sl<CreateManagedCalendarUseCase>(),
      createEvent: sl<CreateCalendarEventUseCase>(),
      updateEvent: sl<UpdateCalendarEventUseCase>(),
      syncGoogle: sl<SyncGoogleCalendarUseCase>(),
    ),
  );
  sl.registerFactory<TaskBloc>(
    () => TaskBloc(
      repository: sl<TaskRepository>(),
      createTask: sl<CreateTaskUseCase>(),
      respondToTask: sl<RespondToTaskUseCase>(),
    ),
  );
  sl.registerFactory<VehicleBloc>(
    () => VehicleBloc(
      repository: sl<VehicleRepository>(),
      updateOdometer: sl<UpdateOdometerUseCase>(),
    ),
  );
  sl.registerFactory<NotificationIngestionBloc>(
    () => NotificationIngestionBloc(repository: sl<NotificationsRepository>()),
  );
}
