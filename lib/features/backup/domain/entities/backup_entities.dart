import 'package:equatable/equatable.dart';

import '../../../../core/backup/lifeos_backup_restore_engine.dart';

/// Canonical collection keys and Vietnamese display labels for LifeOS backups.
abstract final class BackupCollectionCatalog {
  static const String wallets = 'wallets';
  static const String categories = 'categories';
  static const String transactions = 'transactions';
  static const String budgets = 'budgets';
  static const String personalFunds = 'personal_funds';
  static const String fundContributions = 'fund_contributions';
  static const String fundExpenses = 'fund_expenses';
  static const String fundAudits = 'fund_audits';
  static const String calendars = 'calendars';
  static const String tasks = 'tasks';
  static const String events = 'events';
  static const String vehicles = 'vehicles';
  static const String vehicleMaintenances = 'vehicle_maintenances';
  static const String bills = 'bills';
  static const String notes = 'notes';
  static const String documents = 'documents';
  static const String groceryItems = 'grocery_items';
  static const String mealPlans = 'meal_plans';
  static const String utilityReadings = 'utility_readings';
  static const String homeContracts = 'home_contracts';
  static const String subscriptionsWarranties = 'subscriptions_warranties';
  static const String habits = 'habits';
  static const String wellnessDaily = 'wellness_daily';
  static const String giftLedger = 'gift_ledger';
  static const String packingItems = 'packing_items';
  static const String automationRules = 'automation_rules';
  static const String merchantRules = 'merchant_rules';
  static const String aiPersonalizationRules = 'ai_personalization_rules';
  static const String bankAccounts = 'bank_accounts';

  static const List<String> coreKeys = <String>[
    wallets,
    transactions,
    budgets,
    tasks,
    events,
    vehicles,
    notes,
  ];

  static const List<String> extendedKeys = <String>[
    categories,
    calendars,
    vehicleMaintenances,
    bills,
    personalFunds,
    fundContributions,
    fundExpenses,
    fundAudits,
    documents,
    groceryItems,
    mealPlans,
    utilityReadings,
    homeContracts,
    subscriptionsWarranties,
    habits,
    wellnessDaily,
    giftLedger,
    packingItems,
    automationRules,
    merchantRules,
    aiPersonalizationRules,
    bankAccounts,
  ];

  static const List<String> allKeys = <String>[...coreKeys, ...extendedKeys];

  static const Map<String, String> labelsVi = <String, String>{
    wallets: 'Ví & Tài khoản',
    categories: 'Danh mục thu chi',
    transactions: 'Giao dịch sổ cái',
    budgets: 'Ngân sách tháng',
    personalFunds: 'Quỹ tiết kiệm cá nhân',
    fundContributions: 'Khoản nạp quỹ cá nhân',
    fundExpenses: 'Khoản chi quỹ cá nhân',
    fundAudits: 'Nhật ký quỹ cá nhân',
    calendars: 'Bộ lịch cá nhân',
    tasks: 'Công việc cá nhân',
    events: 'Sự kiện lịch riêng',
    vehicles: 'Phương tiện',
    vehicleMaintenances: 'Lịch sử bảo dưỡng xe',
    bills: 'Hóa đơn định kỳ',
    notes: 'Ghi chú đời sống',
    documents: 'Kho giấy tờ (chỉ metadata)',
    groceryItems: 'Danh sách đi chợ & tủ lạnh',
    mealPlans: 'Thực đơn hằng ngày',
    utilityReadings: 'Chỉ số điện nước',
    homeContracts: 'Thông tin nhà cửa & hợp đồng',
    subscriptionsWarranties: 'Gói đăng ký & bảo hành',
    habits: 'Thói quen',
    wellnessDaily: 'Nhật ký nước & tập trung',
    giftLedger: 'Sổ hiếu hỷ',
    packingItems: 'Danh sách hành lý',
    automationRules: 'Quy tắc tự động hóa',
    merchantRules: 'Quy tắc gán danh mục cũ',
    aiPersonalizationRules: 'Cá nhân hóa AI tài chính',
    bankAccounts: 'Tài khoản ngân hàng nhận tiền',
  };

  static String labelFor(String key) => labelsVi[key] ?? key;

  static const List<String> defaultLimitationsVi = <String>[
    'Ảnh hóa đơn và tệp nhị phân đính kèm trong Kho giấy tờ được mã hóa cục bộ trên thiết bị nên không nằm trong tệp sao lưu JSON.',
    'Không gian Gia đình dùng chung và lịch sử kiểm toán gốc của hệ thống cần tham gia lại nhóm bằng mã mời sau khi cài đặt lại.',
  ];
}

enum BackupShareStatus { shared, cancelled, failed }

class BackupShareOutcome extends Equatable {
  final BackupShareStatus status;
  final String fileName;
  final String? filePath;
  final String messageVi;

  const BackupShareOutcome({
    required this.status,
    required this.fileName,
    this.filePath,
    required this.messageVi,
  });

  bool get isShared => status == BackupShareStatus.shared;
  bool get isCancelled => status == BackupShareStatus.cancelled;

  @override
  List<Object?> get props => [status, fileName, filePath, messageVi];
}

class BackupOwnerDataSummary extends Equatable {
  final String ownerId;
  final Map<String, int> countsByCollection;
  final DateTime loadedAt;

  const BackupOwnerDataSummary({
    required this.ownerId,
    required this.countsByCollection,
    required this.loadedAt,
  });

  int countOf(String key) => countsByCollection[key] ?? 0;

  int get walletCount => countOf(BackupCollectionCatalog.wallets);
  int get transactionCount => countOf(BackupCollectionCatalog.transactions);
  int get budgetCount => countOf(BackupCollectionCatalog.budgets);
  int get taskCount => countOf(BackupCollectionCatalog.tasks);
  int get eventCount => countOf(BackupCollectionCatalog.events);
  int get vehicleCount => countOf(BackupCollectionCatalog.vehicles);
  int get noteCount => countOf(BackupCollectionCatalog.notes);

  int get extendedCount => BackupCollectionCatalog.extendedKeys.fold<int>(
    0,
    (sum, k) => sum + countOf(k),
  );

  int get totalRecordCount =>
      countsByCollection.values.fold<int>(0, (sum, c) => sum + c);

  @override
  List<Object?> get props => [ownerId, countsByCollection, loadedAt];
}

class BackupExportBundle extends Equatable {
  final String archiveContent;
  final String fileName;
  final String mimeType;
  final BackupOwnerDataSummary summary;
  final bool encrypted;
  final int schemaVersion;
  final String archiveSha256;
  final List<String> limitationsVi;

  const BackupExportBundle({
    required this.archiveContent,
    required this.fileName,
    required this.mimeType,
    required this.summary,
    required this.encrypted,
    required this.schemaVersion,
    required this.archiveSha256,
    this.limitationsVi = BackupCollectionCatalog.defaultLimitationsVi,
  });

  @override
  List<Object?> get props => [
    archiveContent,
    fileName,
    mimeType,
    summary,
    encrypted,
    schemaVersion,
    archiveSha256,
    limitationsVi,
  ];
}

class BackupArchivePreview extends Equatable {
  final int schemaVersion;
  final String ownerId;
  final DateTime exportedAt;
  final bool checksumVerified;
  final bool wasEncrypted;
  final bool isLegacyFormat;
  final String archiveSha256;
  final Map<String, List<Map<String, dynamic>>> collections;
  final List<String> warnings;
  final List<String> limitationsVi;

  const BackupArchivePreview({
    required this.schemaVersion,
    required this.ownerId,
    required this.exportedAt,
    required this.checksumVerified,
    required this.wasEncrypted,
    this.isLegacyFormat = false,
    required this.archiveSha256,
    required this.collections,
    this.warnings = const <String>[],
    this.limitationsVi = BackupCollectionCatalog.defaultLimitationsVi,
  });

  int countOf(String key) => (collections[key] ?? const []).length;

  int get walletCount => countOf(BackupCollectionCatalog.wallets);
  int get transactionCount => countOf(BackupCollectionCatalog.transactions);
  int get budgetCount => countOf(BackupCollectionCatalog.budgets);
  int get taskCount => countOf(BackupCollectionCatalog.tasks);
  int get eventCount => countOf(BackupCollectionCatalog.events);
  int get vehicleCount => countOf(BackupCollectionCatalog.vehicles);
  int get noteCount => countOf(BackupCollectionCatalog.notes);

  int get extendedCount {
    var total = 0;
    for (final entry in collections.entries) {
      if (!BackupCollectionCatalog.coreKeys.contains(entry.key)) {
        total += entry.value.length;
      }
    }
    return total;
  }

  int get totalRecordCount =>
      collections.values.fold<int>(0, (sum, list) => sum + list.length);

  Map<String, int> get countsByCollection => <String, int>{
    for (final entry in collections.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value.length,
  };

  @override
  List<Object?> get props => [
    schemaVersion,
    ownerId,
    exportedAt,
    checksumVerified,
    wasEncrypted,
    isLegacyFormat,
    archiveSha256,
    collections,
    warnings,
    limitationsVi,
  ];
}

class BackupCollectionCommitStats extends Equatable {
  final String collectionKey;
  final String labelVi;
  final int plannedCount;
  final int committedCount;
  final int skippedCount;
  final int failedCount;

  const BackupCollectionCommitStats({
    required this.collectionKey,
    required this.labelVi,
    required this.plannedCount,
    required this.committedCount,
    required this.skippedCount,
    required this.failedCount,
  });

  @override
  List<Object?> get props => [
    collectionKey,
    labelVi,
    plannedCount,
    committedCount,
    skippedCount,
    failedCount,
  ];
}

class BackupWalletBalanceCheck extends Equatable {
  final String walletId;
  final String walletName;
  final int expectedBalanceMinor;
  final int actualBalanceMinor;
  final bool matched;
  final bool isFromBackup;

  const BackupWalletBalanceCheck({
    required this.walletId,
    required this.walletName,
    required this.expectedBalanceMinor,
    required this.actualBalanceMinor,
    required this.matched,
    this.isFromBackup = true,
  });

  int get deltaMinor => actualBalanceMinor - expectedBalanceMinor;

  @override
  List<Object?> get props => [
    walletId,
    walletName,
    expectedBalanceMinor,
    actualBalanceMinor,
    matched,
    isFromBackup,
  ];
}

class BackupExecutionProgress extends Equatable {
  final String stageLabelVi;
  final int completedUnits;
  final int totalUnits;

  const BackupExecutionProgress({
    required this.stageLabelVi,
    required this.completedUnits,
    required this.totalUnits,
  });

  double? get fraction =>
      totalUnits > 0 ? (completedUnits / totalUnits).clamp(0.0, 1.0) : null;

  @override
  List<Object?> get props => [stageLabelVi, completedUnits, totalUnits];
}

class BackupRestoreExecutionReport extends Equatable {
  final BackupRestoreMode mode;
  final int plannedCount;
  final int committedCount;
  final int skippedCount;
  final int failedCount;
  final int migratedLegacyRecords;
  final List<BackupCollectionCommitStats> perCollectionStats;
  final List<BackupWalletBalanceCheck> walletBalanceChecks;
  final List<String> failureMessages;
  final List<String> warnings;
  final List<String> detailsVi;

  const BackupRestoreExecutionReport({
    required this.mode,
    required this.plannedCount,
    required this.committedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.migratedLegacyRecords,
    required this.perCollectionStats,
    required this.walletBalanceChecks,
    this.failureMessages = const <String>[],
    this.warnings = const <String>[],
    required this.detailsVi,
  });

  bool get hasBalanceMismatches => walletBalanceChecks.any((w) => !w.matched);

  bool get isPartialFailure => failedCount > 0;

  bool get isCleanSuccess => !isPartialFailure && !hasBalanceMismatches;

  @override
  List<Object?> get props => [
    mode,
    plannedCount,
    committedCount,
    skippedCount,
    failedCount,
    migratedLegacyRecords,
    perCollectionStats,
    walletBalanceChecks,
    failureMessages,
    warnings,
    detailsVi,
  ];
}
