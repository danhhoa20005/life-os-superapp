import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get_it/get_it.dart';

import '../../features/backup/data/datasources/firestore_backup_remote_datasource.dart';
import '../../features/backup/data/repositories/backup_repository_impl.dart';
import '../../features/backup/data/services/backup_file_share_service_impl.dart';
import '../../features/backup/domain/repositories/backup_file_share_service.dart';
import '../../features/backup/domain/repositories/backup_repository.dart';
import '../../features/backup/domain/usecases/backup_usecases.dart';
import '../../features/backup/presentation/bloc/backup_bloc.dart';
import '../../features/transactions/data/datasources/transaction_remote_datasource.dart';
import '../../features/transactions/data/repositories/transaction_repository_impl.dart';
import '../../features/transactions/domain/repositories/transaction_repository.dart';
import '../../features/transactions/domain/usecases/transaction_usecases.dart';

/// Registers Backup & Restore Clean Architecture dependencies into [sl].
/// Lead integrates this via a single call inside `configureDependencies(...)`.
void registerBackupDependencies(GetIt sl) {
  if (!sl.isRegistered<BackupFileShareService>()) {
    sl.registerLazySingleton<BackupFileShareService>(
      () => const MethodChannelBackupFileShareService(),
    );
  }

  if (!sl.isRegistered<TransactionRepository>()) {
    sl.registerLazySingleton<TransactionRepository>(
      () => TransactionRepositoryImpl(
        TransactionRemoteDataSource(sl<FirebaseFirestore>()),
      ),
    );
  }
  if (!sl.isRegistered<CreateTransactionUseCase>()) {
    sl.registerLazySingleton(
      () => CreateTransactionUseCase(sl<TransactionRepository>()),
    );
  }
  if (!sl.isRegistered<ReverseTransactionUseCase>()) {
    sl.registerLazySingleton(
      () => ReverseTransactionUseCase(sl<TransactionRepository>()),
    );
  }

  if (!sl.isRegistered<FirestoreBackupRemoteDataSource>()) {
    sl.registerLazySingleton<FirestoreBackupRemoteDataSource>(
      () => FirestoreBackupRemoteDataSource(
        firestore: sl<FirebaseFirestore>(),
        transactionRepository: sl<TransactionRepository>(),
        createTransactionUseCase: sl<CreateTransactionUseCase>(),
        reverseTransactionUseCase: sl<ReverseTransactionUseCase>(),
      ),
    );
  }

  if (!sl.isRegistered<BackupRepository>()) {
    sl.registerLazySingleton<BackupRepository>(
      () => BackupRepositoryImpl(
        remoteDataSource: sl<FirestoreBackupRemoteDataSource>(),
      ),
    );
  }

  if (!sl.isRegistered<LoadBackupOwnerSummaryUseCase>()) {
    sl.registerLazySingleton(
      () => LoadBackupOwnerSummaryUseCase(sl<BackupRepository>()),
    );
  }
  if (!sl.isRegistered<ExportFullBackupUseCase>()) {
    sl.registerLazySingleton(
      () => ExportFullBackupUseCase(sl<BackupRepository>()),
    );
  }
  if (!sl.isRegistered<ExportTransactionsCsvUseCase>()) {
    sl.registerLazySingleton(
      () => ExportTransactionsCsvUseCase(sl<BackupRepository>()),
    );
  }
  if (!sl.isRegistered<PreviewBackupArchiveUseCase>()) {
    sl.registerLazySingleton(
      () => PreviewBackupArchiveUseCase(sl<BackupRepository>()),
    );
  }
  if (!sl.isRegistered<RestoreBackupArchiveUseCase>()) {
    sl.registerLazySingleton(
      () => RestoreBackupArchiveUseCase(sl<BackupRepository>()),
    );
  }

  if (!sl.isRegistered<BackupBloc>()) {
    sl.registerFactory<BackupBloc>(
      () => BackupBloc(
        loadSummary: sl<LoadBackupOwnerSummaryUseCase>(),
        exportFullBackup: sl<ExportFullBackupUseCase>(),
        exportTransactionsCsv: sl<ExportTransactionsCsvUseCase>(),
        previewArchive: sl<PreviewBackupArchiveUseCase>(),
        restoreArchive: sl<RestoreBackupArchiveUseCase>(),
        fileShareService: sl<BackupFileShareService>(),
      ),
    );
  }
}
