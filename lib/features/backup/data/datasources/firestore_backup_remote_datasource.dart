import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/backup/lifeos_backup_restore_engine.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../transactions/data/models/transaction_models.dart';
import '../../../transactions/domain/entities/ledger_integrity_engine.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../../transactions/domain/usecases/transaction_usecases.dart';
import '../../domain/entities/backup_entities.dart';
import '../../domain/services/backup_archive_codec.dart';

typedef BackupWriteHook =
    Future<void> Function(String collectionKey, String docId, int writeIndex);

class FirestoreBackupRemoteDataSource {
  final FirebaseFirestore _firestore;
  final TransactionRepository _transactionRepository;
  final CreateTransactionUseCase _createTransactionUseCase;
  final ReverseTransactionUseCase _reverseTransactionUseCase;
  final BackupWriteHook? _onBeforeWrite;
  final int _pageSize;

  const FirestoreBackupRemoteDataSource({
    required FirebaseFirestore firestore,
    required TransactionRepository transactionRepository,
    required CreateTransactionUseCase createTransactionUseCase,
    required ReverseTransactionUseCase reverseTransactionUseCase,
    @visibleForTesting BackupWriteHook? onBeforeWrite,
    int pageSize = 200,
  }) : _firestore = firestore,
       _transactionRepository = transactionRepository,
       _createTransactionUseCase = createTransactionUseCase,
       _reverseTransactionUseCase = reverseTransactionUseCase,
       _onBeforeWrite = onBeforeWrite,
       _pageSize = pageSize < 1 ? 1 : pageSize;

  DocumentReference<Map<String, dynamic>> _userRef(String userId) =>
      _firestore.collection('users').doc(userId);

  CollectionReference<Map<String, dynamic>> _userCol(
    String userId,
    String colName,
  ) => _userRef(userId).collection(colName);

  static const Map<String, String>
  _firestoreCollectionByBackupKey = <String, String>{
    BackupCollectionCatalog.wallets: 'wallets',
    BackupCollectionCatalog.categories: 'categories',
    BackupCollectionCatalog.transactions: 'transactions',
    BackupCollectionCatalog.budgets: 'budgets',
    BackupCollectionCatalog.personalFunds: 'personal_funds',
    BackupCollectionCatalog.calendars: 'calendars',
    BackupCollectionCatalog.tasks: 'personal_tasks',
    BackupCollectionCatalog.events: 'private_events',
    BackupCollectionCatalog.vehicles: 'vehicles',
    BackupCollectionCatalog.bills: 'bills',
    BackupCollectionCatalog.notes: 'life_notes',
    BackupCollectionCatalog.documents: 'documents',
    BackupCollectionCatalog.groceryItems: 'grocery_items',
    BackupCollectionCatalog.mealPlans: 'meal_plans',
    BackupCollectionCatalog.utilityReadings: 'utility_readings',
    BackupCollectionCatalog.homeContracts: 'home_contracts',
    BackupCollectionCatalog.subscriptionsWarranties: 'subscriptions_warranties',
    BackupCollectionCatalog.habits: 'habits',
    BackupCollectionCatalog.wellnessDaily: 'wellness_daily',
    BackupCollectionCatalog.giftLedger: 'gift_ledger',
    BackupCollectionCatalog.packingItems: 'packing_items',
    BackupCollectionCatalog.automationRules: 'automation_rules',
    BackupCollectionCatalog.merchantRules: 'merchant_rules',
    BackupCollectionCatalog.aiPersonalizationRules: 'ai_personalization_rules',
    BackupCollectionCatalog.bankAccounts: 'bank_accounts',
  };

  static const Map<String, Set<String>> _defaultTimestampFields =
      <String, Set<String>>{
        BackupCollectionCatalog.wallets: {'createdAt', 'updatedAt'},
        BackupCollectionCatalog.transactions: {
          'occurredAt',
          'receivedAt',
          'createdAt',
          'updatedAt',
        },
        BackupCollectionCatalog.budgets: {'updatedAt'},
        BackupCollectionCatalog.personalFunds: {'createdAt', 'updatedAt'},
        BackupCollectionCatalog.fundContributions: {'createdAt'},
        BackupCollectionCatalog.fundExpenses: {
          'decidedAt',
          'executedAt',
          'disputedAt',
          'createdAt',
          'updatedAt',
        },
        BackupCollectionCatalog.fundAudits: {'createdAt'},
        BackupCollectionCatalog.calendars: {'lastSyncedAt', 'updatedAt'},
        BackupCollectionCatalog.tasks: {'dueAt', 'createdAt', 'updatedAt'},
        BackupCollectionCatalog.events: {
          'startsAt',
          'endsAt',
          'createdAt',
          'updatedAt',
        },
        BackupCollectionCatalog.vehicles: {
          'lastServiceDate',
          'insuranceExpiryDate',
          'inspectionExpiryDate',
          'createdAt',
          'updatedAt',
        },
        BackupCollectionCatalog.vehicleMaintenances: {'serviceDate'},
        BackupCollectionCatalog.bills: {'nextDueDate', 'createdAt'},
        BackupCollectionCatalog.automationRules: {'updatedAt'},
        BackupCollectionCatalog.merchantRules: {'updatedAt'},
        BackupCollectionCatalog.aiPersonalizationRules: {'lastCorrectedAt'},
        BackupCollectionCatalog.bankAccounts: {'createdAt'},
      };

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _fetchCollectionPaginated(Query<Map<String, dynamic>> baseQuery) async {
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      var query = baseQuery.orderBy(FieldPath.documentId);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }
      final snap = await query.limit(_pageSize).get();
      if (snap.docs.isEmpty) break;
      docs.addAll(snap.docs);
      if (snap.docs.length < _pageSize) break;
      cursor = snap.docs.last;
    }
    return docs;
  }

  Future<Map<String, List<Map<String, dynamic>>>> fetchAllOwnerCollections({
    required String ownerId,
  }) async {
    final walletsRes = await _transactionRepository.fetchAllWalletsPaginated(
      userId: ownerId,
      pageSize: _pageSize,
    );
    if (walletsRes is Err<List<WalletEntity>>) {
      throw AppException(
        code: walletsRes.failure.code,
        message: walletsRes.failure.message,
      );
    }
    final wallets = (walletsRes as Success<List<WalletEntity>>).value;

    final categoriesRes = await _transactionRepository
        .fetchAllCategoriesPaginated(userId: ownerId, pageSize: _pageSize);
    if (categoriesRes is Err<List<CategoryEntity>>) {
      throw AppException(
        code: categoriesRes.failure.code,
        message: categoriesRes.failure.message,
      );
    }
    final categories = (categoriesRes as Success<List<CategoryEntity>>).value;

    final txRes = await _transactionRepository.fetchAllTransactionsPaginated(
      userId: ownerId,
      pageSize: _pageSize,
    );
    if (txRes is Err<List<TransactionEntity>>) {
      throw AppException(
        code: txRes.failure.code,
        message: txRes.failure.message,
      );
    }
    final transactions = (txRes as Success<List<TransactionEntity>>).value;

    final result = <String, List<Map<String, dynamic>>>{
      BackupCollectionCatalog.wallets: wallets.map(_walletEntityToMap).toList(),
      BackupCollectionCatalog.categories: categories
          .map(_categoryEntityToMap)
          .toList(),
      BackupCollectionCatalog.transactions: transactions
          .map(_transactionEntityToMap)
          .toList(),
    };

    for (final entry in _firestoreCollectionByBackupKey.entries) {
      final key = entry.key;
      if (result.containsKey(key)) continue;
      final colDocs = await _fetchCollectionPaginated(
        _userCol(ownerId, entry.value),
      );
      if (key == BackupCollectionCatalog.events) {
        result[key] = colDocs
            .where((d) => d.data()['syncStatus']?.toString() != 'pendingDelete')
            .map((d) => _sanitizeFirestoreDoc(d.id, d.data()))
            .toList();
      } else if (key == BackupCollectionCatalog.documents) {
        result[key] = colDocs.map((d) {
          final map = _sanitizeFirestoreDoc(d.id, d.data());
          final hadLocalFile =
              (map['localAttachmentPath']?.toString().isNotEmpty ?? false) ||
              (map['localAttachmentStorageKey']?.toString().isNotEmpty ??
                  false);
          map.remove('localAttachmentPath');
          if (hadLocalFile) {
            map['localAttachmentOmitted'] = true;
          }
          return map;
        }).toList();
      } else {
        result[key] = colDocs
            .map((d) => _sanitizeFirestoreDoc(d.id, d.data()))
            .toList();
      }

      if (key == BackupCollectionCatalog.vehicles) {
        final maintList = <Map<String, dynamic>>[];
        for (final vDoc in colDocs) {
          final mDocs = await _fetchCollectionPaginated(
            vDoc.reference.collection('maintenances'),
          );
          for (final mDoc in mDocs) {
            final mMap = _sanitizeFirestoreDoc(mDoc.id, mDoc.data());
            mMap['vehicleId'] = vDoc.id;
            maintList.add(mMap);
          }
        }
        result[BackupCollectionCatalog.vehicleMaintenances] = maintList;
      }

      if (key == BackupCollectionCatalog.personalFunds) {
        final contribs = <Map<String, dynamic>>[];
        final expenses = <Map<String, dynamic>>[];
        final audits = <Map<String, dynamic>>[];
        for (final fDoc in colDocs) {
          final cDocs = await _fetchCollectionPaginated(
            fDoc.reference.collection('contributions'),
          );
          for (final cDoc in cDocs) {
            final cMap = _sanitizeFirestoreDoc(cDoc.id, cDoc.data());
            cMap['fundId'] = fDoc.id;
            contribs.add(cMap);
          }
          final eDocs = await _fetchCollectionPaginated(
            fDoc.reference.collection('expenses'),
          );
          for (final eDoc in eDocs) {
            final eMap = _sanitizeFirestoreDoc(eDoc.id, eDoc.data());
            eMap['fundId'] = fDoc.id;
            expenses.add(eMap);
          }
          final aDocs = await _fetchCollectionPaginated(
            fDoc.reference.collection('fund_audits'),
          );
          for (final aDoc in aDocs) {
            final aMap = _sanitizeFirestoreDoc(aDoc.id, aDoc.data());
            aMap['fundId'] = fDoc.id;
            audits.add(aMap);
          }
        }
        result[BackupCollectionCatalog.fundContributions] = contribs;
        result[BackupCollectionCatalog.fundExpenses] = expenses;
        result[BackupCollectionCatalog.fundAudits] = audits;
      }
    }

    return result;
  }

  Future<BackupOwnerDataSummary> loadOwnerSummary({
    required String ownerId,
  }) async {
    final collections = await fetchAllOwnerCollections(ownerId: ownerId);
    final counts = <String, int>{
      for (final entry in collections.entries) entry.key: entry.value.length,
    };
    return BackupOwnerDataSummary(
      ownerId: ownerId,
      countsByCollection: counts,
      loadedAt: DateTime.now().toUtc(),
    );
  }

  static bool _isImmutableVerifiedBankTx(
    TransactionEntity tx, [
    Map<String, dynamic>? rawData,
  ]) {
    final verStatusUpper =
        (tx.verificationStatus ??
                rawData?['verificationStatus']?.toString() ??
                '')
            .toUpperCase();
    final rawVerLower = (rawData?['verification']?.toString() ?? '')
        .toLowerCase();
    final rawSource = rawData?['sourceKind']?.toString() ?? '';
    return tx.verification == TransactionVerification.verified ||
        rawVerLower == 'verified' ||
        rawVerLower == 'verifiedbybank' ||
        rawVerLower == 'verified_by_bank' ||
        verStatusUpper == 'VERIFIED' ||
        verStatusUpper == 'VERIFIEDBYBANK' ||
        verStatusUpper == 'VERIFIED_BY_BANK' ||
        tx.sourceKind == TransactionSourceKind.bankWebhook ||
        tx.sourceKind == TransactionSourceKind.bankApi ||
        rawSource == 'bankWebhook' ||
        rawSource == 'bankApi';
  }

  Future<BackupRestoreExecutionReport> restoreAllOwnerCollections({
    required String targetUserId,
    required BackupArchivePreview preview,
    required BackupRestoreMode mode,
    required bool explicitReplaceConfirmation,
    void Function(BackupExecutionProgress progress)? onProgress,
  }) async {
    if (mode == BackupRestoreMode.replaceConfirmed &&
        !explicitReplaceConfirmation) {
      throw StateError('Chế độ ghi đè yêu cầu người dùng xác nhận tường minh.');
    }

    // Step 1 (DATA-02): Dry-run validation BEFORE touching any Firestore records.
    if (!preview.checksumVerified) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Bản sao lưu chưa được xác thực toàn vẹn SHA-256.',
      );
    }
    if (preview.schemaVersion < BackupArchiveCodec.minSupportedSchemaVersion ||
        preview.schemaVersion > BackupArchiveCodec.currentSchemaVersion) {
      throw AppException(
        code: 'VALIDATION_FAILURE',
        message:
            'Phiên bản schema sao lưu v${preview.schemaVersion} không được hỗ trợ.',
      );
    }

    final existingWalletsRes = await _transactionRepository
        .fetchAllWalletsPaginated(userId: targetUserId, pageSize: _pageSize);
    if (existingWalletsRes is Err<List<WalletEntity>>) {
      throw AppException(
        code: existingWalletsRes.failure.code,
        message: existingWalletsRes.failure.message,
      );
    }
    final existingWallets =
        (existingWalletsRes as Success<List<WalletEntity>>).value;
    final existingWalletsById = <String, WalletEntity>{
      for (final w in existingWallets) w.id: w,
    };

    final existingTxRes = await _transactionRepository
        .fetchAllTransactionsPaginated(
          userId: targetUserId,
          pageSize: _pageSize,
        );
    if (existingTxRes is Err<List<TransactionEntity>>) {
      throw AppException(
        code: existingTxRes.failure.code,
        message: existingTxRes.failure.message,
      );
    }
    final existingTxs =
        (existingTxRes as Success<List<TransactionEntity>>).value;
    final existingTxById = <String, TransactionEntity>{
      for (final tx in existingTxs) tx.id: tx,
    };
    final rawExistingTxDocs = await _fetchCollectionPaginated(
      _userCol(targetUserId, 'transactions'),
    );
    final rawExistingTxById = <String, Map<String, dynamic>>{
      for (final d in rawExistingTxDocs) d.id: d.data(),
    };
    final immutableVerifiedTxIds = <String>{};
    final verifiedProtectedWalletIds = <String>{};
    for (final tx in existingTxs) {
      if (_isImmutableVerifiedBankTx(tx, rawExistingTxById[tx.id])) {
        immutableVerifiedTxIds.add(tx.id);
        if (tx.walletId.isNotEmpty) {
          verifiedProtectedWalletIds.add(tx.walletId);
        }
        if (tx.targetWalletId != null && tx.targetWalletId!.isNotEmpty) {
          verifiedProtectedWalletIds.add(tx.targetWalletId!);
        }
      }
    }

    final archiveTag = preview.archiveSha256.length >= 6
        ? preview.archiveSha256.substring(0, 6)
        : 'imp';
    final importSessionId =
        'imp_${DateTime.now().microsecondsSinceEpoch}_$archiveTag';

    String mapDocId(String colKey, String origId, int index) {
      final cleanOrig = origId.trim();
      if (mode != BackupRestoreMode.importAsNew) {
        return cleanOrig.isNotEmpty ? cleanOrig : 'restored_${colKey}_$index';
      }
      return cleanOrig.isNotEmpty
          ? 'imp_${archiveTag}_$cleanOrig'
          : 'imp_${archiveTag}_${colKey}_$index';
    }

    // 1. Parse wallets & build deterministic wallet ID remap.
    final rawWallets =
        preview.collections[BackupCollectionCatalog.wallets] ??
        const <Map<String, dynamic>>[];
    final walletIdMap = <String, String>{};
    final incomingWallets = <_IncomingWalletSpec>[];
    for (var i = 0; i < rawWallets.length; i++) {
      final w = rawWallets[i];
      final origId = (w['id'] ?? '').toString().trim();
      final mappedId = mapDocId(BackupCollectionCatalog.wallets, origId, i);
      if (origId.isNotEmpty) {
        walletIdMap[origId] = mappedId;
      }
      walletIdMap[mappedId] = mappedId;
      incomingWallets.add(
        _IncomingWalletSpec(
          origId: origId.isNotEmpty ? origId : mappedId,
          targetId: mappedId,
          name: (w['name'] ?? 'Ví khôi phục').toString().trim().isEmpty
              ? 'Ví khôi phục'
              : (w['name'] ?? 'Ví khôi phục').toString().trim(),
          type: _parseWalletType((w['type'] ?? 'cash').toString()),
          recordedBalanceMinor: (w['balanceMinor'] as num?)?.toInt() ?? 0,
          hasRecordedBalance: w.containsKey('balanceMinor'),
          bankCode: w['bankCode']?.toString(),
          maskedAccount: w['maskedAccount']?.toString(),
          creditLimitMinor: (w['creditLimitMinor'] as num?)?.toInt(),
          isEstimatedBalance: (w['isEstimatedBalance'] as bool?) ?? true,
          raw: w,
        ),
      );
    }

    String resolveWalletId(String? origWalletId) {
      final clean = (origWalletId ?? '').trim();
      if (clean.isEmpty) {
        if (incomingWallets.isNotEmpty) return incomingWallets.first.targetId;
        if (existingWallets.isNotEmpty) return existingWallets.first.id;
        return mode == BackupRestoreMode.importAsNew
            ? 'imp_${archiveTag}_wallet_cash_default'
            : 'wallet_cash_default';
      }
      return walletIdMap[clean] ??
          (mode == BackupRestoreMode.importAsNew
              ? 'imp_${archiveTag}_$clean'
              : clean);
    }

    // 2. Parse transactions, validate wallet references & build deterministic ID remap.
    final rawTxs =
        preview.collections[BackupCollectionCatalog.transactions] ??
        const <Map<String, dynamic>>[];
    final enforceStrictWalletRefs =
        rawWallets.isNotEmpty || preview.schemaVersion >= 3;
    if (enforceStrictWalletRefs && rawTxs.isNotEmpty) {
      for (var i = 0; i < rawTxs.length; i++) {
        final raw = rawTxs[i];
        final rawWalletId = (raw['walletId'] ?? '').toString().trim();
        final rawTargetWalletId = (raw['targetWalletId'] ?? '')
            .toString()
            .trim();
        bool isKnownWalletRef(String wId) {
          if (wId.isEmpty) return true;
          if (walletIdMap.containsKey(wId)) return true;
          if (mode != BackupRestoreMode.replaceConfirmed &&
              existingWalletsById.containsKey(wId)) {
            return true;
          }
          return false;
        }

        if (!isKnownWalletRef(rawWalletId)) {
          throw AppException(
            code: 'VALIDATION_FAILURE',
            message:
                'Bản sao lưu không nhất quán: giao dịch "${raw['id'] ?? i}" tham chiếu ví "$rawWalletId" không tồn tại.',
          );
        }
        if (!isKnownWalletRef(rawTargetWalletId)) {
          throw AppException(
            code: 'VALIDATION_FAILURE',
            message:
                'Bản sao lưu không nhất quán: giao dịch "${raw['id'] ?? i}" tham chiếu ví đích "$rawTargetWalletId" không tồn tại.',
          );
        }
      }
    }

    final txIdMap = <String, String>{};
    for (var i = 0; i < rawTxs.length; i++) {
      final raw = rawTxs[i];
      final origId = (raw['id'] ?? '').toString().trim();
      final kind = _parseTransactionKind((raw['kind'] ?? 'expense').toString());
      final revOf = raw['reversalOfId']?.toString().trim();
      if (kind != TransactionKind.reversal && origId.isNotEmpty) {
        txIdMap[origId] = mapDocId(
          BackupCollectionCatalog.transactions,
          origId,
          i,
        );
      } else if (kind == TransactionKind.reversal &&
          origId.isNotEmpty &&
          (revOf == null || revOf.isEmpty)) {
        txIdMap[origId] = mapDocId(
          BackupCollectionCatalog.transactions,
          origId,
          i,
        );
      }
    }

    final incomingTxs = <_IncomingTxSpec>[];
    for (var i = 0; i < rawTxs.length; i++) {
      final raw = rawTxs[i];
      final origId = (raw['id'] ?? '').toString().trim();
      final kind = _parseTransactionKind((raw['kind'] ?? 'expense').toString());
      final origRevOf = raw['reversalOfId']?.toString().trim();
      final mappedRevOf = (origRevOf != null && origRevOf.isNotEmpty)
          ? (txIdMap[origRevOf] ??
                (mode == BackupRestoreMode.importAsNew
                    ? 'imp_${archiveTag}_$origRevOf'
                    : origRevOf))
          : null;

      late final String targetTxId;
      if (kind == TransactionKind.reversal &&
          mappedRevOf != null &&
          origId == 'rev_$origRevOf') {
        targetTxId = 'rev_$mappedRevOf';
      } else if (origId.isNotEmpty && txIdMap.containsKey(origId)) {
        targetTxId = txIdMap[origId]!;
      } else {
        targetTxId = mapDocId(BackupCollectionCatalog.transactions, origId, i);
      }
      if (origId.isNotEmpty) {
        txIdMap[origId] = targetTxId;
      }

      final mappedWalletId = resolveWalletId(raw['walletId']?.toString());
      final rawTargetWallet = raw['targetWalletId']?.toString().trim();
      final mappedTargetWalletId =
          (rawTargetWallet != null && rawTargetWallet.isNotEmpty)
          ? resolveWalletId(rawTargetWallet)
          : null;

      final verification = _parseVerification(raw['verification']?.toString());
      final direction = _resolveDirection(
        kind: kind,
        rawDirection: raw['direction']?.toString(),
      );
      final amountMinor =
          ((raw['amountMinor'] ?? raw['amount']) as num?)?.toInt() ?? 0;
      final splitLines = _parseSplitLines(raw['splitLines']);

      incomingTxs.add(
        _IncomingTxSpec(
          origId: origId,
          targetId: targetTxId,
          mappedWalletId: mappedWalletId,
          mappedTargetWalletId: mappedTargetWalletId,
          mappedReversalOfId: mappedRevOf,
          categoryId: raw['categoryId']?.toString(),
          categoryName: (raw['categoryName'] ?? 'Chi tiêu khác').toString(),
          kind: kind,
          direction: direction,
          amountMinor: amountMinor,
          merchant: (raw['merchant'] ?? '').toString(),
          note: raw['note']?.toString(),
          occurredAt:
              _parseDateTime(raw['occurredAt']) ?? DateTime.now().toUtc(),
          sourceKind: _parseSourceKind(raw['sourceKind']?.toString()),
          verification: verification,
          verificationStatus: raw['verificationStatus']?.toString(),
          isRefund: raw['isRefund'] == true,
          isVehicleMaintenanceHint: raw['isVehicleMaintenanceHint'] == true,
          isRecurringCandidate: raw['isRecurringCandidate'] == true,
          splitLines: splitLines,
          balanceAfterMinor: (raw['balanceAfterMinor'] as num?)?.toInt(),
          observedBalanceMinor: (raw['observedBalanceMinor'] as num?)?.toInt(),
          referenceCode: raw['referenceCode']?.toString(),
          bankCode: raw['bankCode']?.toString(),
          accountMasked: raw['accountMasked']?.toString(),
          counterpartyDisplay: raw['counterpartyDisplay']?.toString(),
          externalTransactionId: raw['externalTransactionId']?.toString(),
          connectionId: raw['connectionId']?.toString(),
          sourceProvider: raw['sourceProvider']?.toString(),
          reconciliationStatus: raw['reconciliationStatus']?.toString(),
          sourceEventKey: raw['sourceEventKey']?.toString(),
          receivedAt: _parseDateTime(raw['receivedAt']),
          ledgerApplied: raw['ledgerApplied'] is bool
              ? raw['ledgerApplied'] as bool
              : (verification == TransactionVerification.userConfirmed ||
                    verification ==
                        TransactionVerification.matchedPaymentOrder ||
                    verification == TransactionVerification.verified),
          raw: raw,
        ),
      );
    }

    // 3. For legacy v1/v2 archives missing `wallets`, synthesize referenced wallets safely.
    final knownIncomingWalletIds = <String>{
      for (final w in incomingWallets) w.targetId,
    };
    if (!enforceStrictWalletRefs) {
      for (final tx in incomingTxs) {
        for (final wId in [tx.mappedWalletId, tx.mappedTargetWalletId]) {
          if (wId == null || wId.isEmpty) continue;
          if (!knownIncomingWalletIds.contains(wId) &&
              !existingWalletsById.containsKey(wId)) {
            knownIncomingWalletIds.add(wId);
            incomingWallets.add(
              _IncomingWalletSpec(
                origId: wId,
                targetId: wId,
                name: tx.raw['walletName']?.toString().trim().isNotEmpty == true
                    ? tx.raw['walletName'].toString().trim()
                    : (wId.contains('wallet_cash_default')
                          ? 'Ví tiền mặt'
                          : 'Ví khôi phục'),
                type: WalletType.cash,
                recordedBalanceMinor: 0,
                hasRecordedBalance: false,
                raw: const <String, dynamic>{},
              ),
            );
          }
        }
      }
    }

    final warnings = <String>[...preview.warnings];
    final failureMessages = <String>[];
    final incomingWalletIdSet = <String>{
      for (final w in incomingWallets) w.targetId,
    };
    final incomingTxIdSet = <String>{for (final t in incomingTxs) t.targetId};

    // Step 2 (DATA-02): Record import checkpoint session BEFORE staging writes.
    // In `replaceConfirmed` mode, NEVER pre-delete existing records prior to restore!
    final checkpointRef = _userCol(
      targetUserId,
      'daily_preferences',
    ).doc('backup_restore_checkpoint');
    await checkpointRef.set({
      'id': 'backup_restore_checkpoint',
      'ownerId': targetUserId,
      'importSessionId': importSessionId,
      'mode': mode.code,
      'status': 'staging',
      'archiveSha256': preview.archiveSha256,
      'startedAt': Timestamp.fromDate(DateTime.now()),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    // Index incoming transactions by targetId so reversal deltas know original kind.
    final incomingTxByTargetId = <String, _IncomingTxSpec>{
      for (final t in incomingTxs) t.targetId: t,
    };

    // 5. Compute pending wallet balance deltas ONLY for transactions that WILL replay
    // (not already committed in `existingTxById`) to avoid double counting!
    final pendingDeltaByWallet = <String, int>{};
    for (final tx in incomingTxs) {
      if (existingTxById.containsKey(tx.targetId)) continue;
      if (!tx.ledgerApplied || tx.amountMinor <= 0) continue;

      if (tx.kind == TransactionKind.transfer ||
          tx.kind == TransactionKind.creditCardPayment) {
        pendingDeltaByWallet[tx.mappedWalletId] =
            (pendingDeltaByWallet[tx.mappedWalletId] ?? 0) - tx.amountMinor;
        if (tx.mappedTargetWalletId != null &&
            tx.mappedTargetWalletId!.isNotEmpty) {
          pendingDeltaByWallet[tx.mappedTargetWalletId!] =
              (pendingDeltaByWallet[tx.mappedTargetWalletId!] ?? 0) +
              tx.amountMinor;
        }
      } else if (tx.kind == TransactionKind.income) {
        pendingDeltaByWallet[tx.mappedWalletId] =
            (pendingDeltaByWallet[tx.mappedWalletId] ?? 0) + tx.amountMinor;
      } else if (tx.kind == TransactionKind.expense) {
        pendingDeltaByWallet[tx.mappedWalletId] =
            (pendingDeltaByWallet[tx.mappedWalletId] ?? 0) - tx.amountMinor;
      } else if (tx.kind == TransactionKind.reversal) {
        final origInBackup = tx.mappedReversalOfId != null
            ? incomingTxByTargetId[tx.mappedReversalOfId!]
            : null;
        final origExisting = tx.mappedReversalOfId != null
            ? existingTxById[tx.mappedReversalOfId!]
            : null;
        final isTransferReversal =
            (tx.mappedTargetWalletId != null &&
                tx.mappedTargetWalletId!.isNotEmpty) ||
            origInBackup?.kind == TransactionKind.transfer ||
            origInBackup?.kind == TransactionKind.creditCardPayment ||
            origExisting?.kind == TransactionKind.transfer ||
            origExisting?.kind == TransactionKind.creditCardPayment;

        if (isTransferReversal) {
          final revTarget =
              tx.mappedTargetWalletId ??
              origInBackup?.mappedTargetWalletId ??
              origExisting?.targetWalletId;
          pendingDeltaByWallet[tx.mappedWalletId] =
              (pendingDeltaByWallet[tx.mappedWalletId] ?? 0) + tx.amountMinor;
          if (revTarget != null && revTarget.isNotEmpty) {
            pendingDeltaByWallet[revTarget] =
                (pendingDeltaByWallet[revTarget] ?? 0) - tx.amountMinor;
          }
        } else {
          final delta = tx.direction == 'credit'
              ? tx.amountMinor
              : -tx.amountMinor;
          pendingDeltaByWallet[tx.mappedWalletId] =
              (pendingDeltaByWallet[tx.mappedWalletId] ?? 0) + delta;
        }
      }
    }

    // Track per-collection stats from ACTUAL committed writes ONLY.
    final statsAcc = <String, _MutableStats>{};
    _MutableStats statsFor(String colKey) => statsAcc.putIfAbsent(
      colKey,
      () => _MutableStats(colKey, BackupCollectionCatalog.labelFor(colKey)),
    );

    statsFor(BackupCollectionCatalog.wallets).plannedCount =
        incomingWallets.length;
    statsFor(BackupCollectionCatalog.transactions).plannedCount =
        incomingTxs.length;

    final otherCollectionsOrder = <String>[
      BackupCollectionCatalog.categories,
      BackupCollectionCatalog.calendars,
      BackupCollectionCatalog.budgets,
      BackupCollectionCatalog.tasks,
      BackupCollectionCatalog.events,
      BackupCollectionCatalog.vehicles,
      BackupCollectionCatalog.vehicleMaintenances,
      BackupCollectionCatalog.bills,
      BackupCollectionCatalog.notes,
      BackupCollectionCatalog.personalFunds,
      BackupCollectionCatalog.fundContributions,
      BackupCollectionCatalog.fundExpenses,
      BackupCollectionCatalog.fundAudits,
      BackupCollectionCatalog.documents,
      BackupCollectionCatalog.groceryItems,
      BackupCollectionCatalog.mealPlans,
      BackupCollectionCatalog.utilityReadings,
      BackupCollectionCatalog.homeContracts,
      BackupCollectionCatalog.subscriptionsWarranties,
      BackupCollectionCatalog.habits,
      BackupCollectionCatalog.wellnessDaily,
      BackupCollectionCatalog.giftLedger,
      BackupCollectionCatalog.packingItems,
      BackupCollectionCatalog.automationRules,
      BackupCollectionCatalog.merchantRules,
      BackupCollectionCatalog.aiPersonalizationRules,
      BackupCollectionCatalog.bankAccounts,
    ];
    for (final colKey in otherCollectionsOrder) {
      final list =
          preview.collections[colKey] ?? const <Map<String, dynamic>>[];
      if (list.isNotEmpty) {
        statsFor(colKey).plannedCount = list.length;
      }
    }

    final totalPlannedUnits =
        incomingWallets.length +
        incomingTxs.length +
        otherCollectionsOrder.fold<int>(
          0,
          (acc, k) => acc + (preview.collections[k]?.length ?? 0),
        );
    var completedUnits = 0;
    var writeIndex = 0;
    var aborted = false;

    void reportProgress(String label) {
      onProgress?.call(
        BackupExecutionProgress(
          stageLabelVi: label,
          completedUnits: completedUnits,
          totalUnits: totalPlannedUnits,
        ),
      );
    }

    // 6. Create missing wallets (or reset in replaceConfirmed when no txs committed yet).
    reportProgress('Đang khôi phục ví & tài khoản...');
    for (final w in incomingWallets) {
      if (aborted) break;
      final existingWallet = existingWalletsById[w.targetId];
      final delta = pendingDeltaByWallet[w.targetId] ?? 0;
      final initialBalance = w.hasRecordedBalance
          ? (w.recordedBalanceMinor - delta)
          : 0;

      if (existingWallet != null) {
        final hasAnyCommittedTxForWallet = existingTxs.any(
          (t) =>
              incomingTxIdSet.contains(t.id) &&
              (t.walletId == w.targetId || t.targetWalletId == w.targetId),
        );
        final isVerifiedProtectedWallet = verifiedProtectedWalletIds.contains(
          w.targetId,
        );
        if (mode == BackupRestoreMode.replaceConfirmed &&
            !isVerifiedProtectedWallet &&
            !hasAnyCommittedTxForWallet &&
            existingWallet.balanceMinor != initialBalance) {
          try {
            writeIndex++;
            if (_onBeforeWrite != null) {
              await _onBeforeWrite(
                BackupCollectionCatalog.wallets,
                w.targetId,
                writeIndex,
              );
            }
            await _resetWalletBalanceWithAudit(
              userId: targetUserId,
              wallet: existingWallet,
              targetBalanceMinor: initialBalance,
              operationTag: 'restore_reset_${w.targetId}_$writeIndex',
              lastRestoredSessionId: importSessionId,
            );
            statsFor(BackupCollectionCatalog.wallets).committedCount++;
          } catch (e) {
            aborted = true;
            failureMessages.add(
              'Gián đoạn khi đặt lại số dư ví "${w.name}": $e',
            );
          }
        } else {
          statsFor(BackupCollectionCatalog.wallets).skippedCount++;
        }
        completedUnits++;
        continue;
      }

      try {
        writeIndex++;
        if (_onBeforeWrite != null) {
          await _onBeforeWrite(
            BackupCollectionCatalog.wallets,
            w.targetId,
            writeIndex,
          );
        }
        final createdWallet = await _createMissingWalletDeterministic(
          userId: targetUserId,
          spec: w,
          openingBalanceMinor: initialBalance,
          lastRestoredSessionId: importSessionId,
        );
        existingWalletsById[w.targetId] = createdWallet;
        statsFor(BackupCollectionCatalog.wallets).committedCount++;
      } catch (e) {
        aborted = true;
        failureMessages.add('Gián đoạn khi tạo ví "${w.name}": $e');
      }
      completedUnits++;
      reportProgress(
        'Đang khôi phục ví (${statsFor(BackupCollectionCatalog.wallets).committedCount}/${incomingWallets.length})...',
      );
    }

    // 7. Replay transactions: Pass 1 = non-reversals; Pass 2 = reversals.
    if (!aborted) {
      reportProgress('Đang khôi phục lịch sử giao dịch...');
    }
    final nonReversals =
        incomingTxs.where((t) => t.kind != TransactionKind.reversal).toList()
          ..sort((a, b) {
            final cmp = a.occurredAt.compareTo(b.occurredAt);
            return cmp != 0 ? cmp : a.targetId.compareTo(b.targetId);
          });

    final reversals =
        incomingTxs.where((t) => t.kind == TransactionKind.reversal).toList()
          ..sort((a, b) {
            final cmp = a.occurredAt.compareTo(b.occurredAt);
            return cmp != 0 ? cmp : a.targetId.compareTo(b.targetId);
          });

    for (final tx in nonReversals) {
      if (aborted) break;
      if (existingTxById.containsKey(tx.targetId)) {
        statsFor(BackupCollectionCatalog.transactions).skippedCount++;
        completedUnits++;
        continue;
      }

      if (tx.amountMinor <= 0) {
        statsFor(BackupCollectionCatalog.transactions).failedCount++;
        failureMessages.add(
          'Giao dịch "${tx.targetId}" có số tiền không hợp lệ (${tx.amountMinor}).',
        );
        completedUnits++;
        continue;
      }

      if ((tx.kind == TransactionKind.transfer ||
              tx.kind == TransactionKind.creditCardPayment) &&
          (tx.mappedTargetWalletId == null ||
              tx.mappedTargetWalletId!.isEmpty ||
              tx.mappedTargetWalletId == tx.mappedWalletId)) {
        statsFor(BackupCollectionCatalog.transactions).failedCount++;
        failureMessages.add(
          'Giao dịch chuyển/trả thẻ "${tx.targetId}" thiếu ví đích hợp lệ.',
        );
        completedUnits++;
        continue;
      }

      try {
        writeIndex++;
        if (_onBeforeWrite != null) {
          await _onBeforeWrite(
            BackupCollectionCatalog.transactions,
            tx.targetId,
            writeIndex,
          );
        }

        final committedTx = await _restoreNonReversalTransaction(
          targetUserId: targetUserId,
          tx: tx,
          lastRestoredSessionId: importSessionId,
        );
        existingTxById[tx.targetId] = committedTx;
        statsFor(BackupCollectionCatalog.transactions).committedCount++;
      } catch (e) {
        aborted = true;
        failureMessages.add(
          'Gián đoạn khi khôi phục giao dịch "${tx.targetId}": $e',
        );
      }
      completedUnits++;
      if (completedUnits % 10 == 0 || completedUnits == totalPlannedUnits) {
        reportProgress(
          'Đang khôi phục giao dịch ($completedUnits/$totalPlannedUnits)...',
        );
      }
    }

    for (final rev in reversals) {
      if (aborted) break;
      if (existingTxById.containsKey(rev.targetId)) {
        statsFor(BackupCollectionCatalog.transactions).skippedCount++;
        completedUnits++;
        continue;
      }

      if (rev.amountMinor <= 0) {
        statsFor(BackupCollectionCatalog.transactions).failedCount++;
        failureMessages.add(
          'Bút toán đảo "${rev.targetId}" có số tiền không hợp lệ.',
        );
        completedUnits++;
        continue;
      }

      try {
        writeIndex++;
        if (_onBeforeWrite != null) {
          await _onBeforeWrite(
            BackupCollectionCatalog.transactions,
            rev.targetId,
            writeIndex,
          );
        }

        final committedRev = await _restoreReversalTransaction(
          targetUserId: targetUserId,
          rev: rev,
          existingTxById: existingTxById,
        );
        existingTxById[rev.targetId] = committedRev;
        statsFor(BackupCollectionCatalog.transactions).committedCount++;
      } catch (e) {
        aborted = true;
        failureMessages.add(
          'Gián đoạn khi khôi phục đảo bút toán "${rev.targetId}": $e',
        );
      }
      completedUnits++;
      if (completedUnits % 10 == 0 || completedUnits == totalPlannedUnits) {
        reportProgress(
          'Đang khôi phục giao dịch ($completedUnits/$totalPlannedUnits)...',
        );
      }
    }

    // 8. Restore remaining collections (vehicles before maintenances, funds before subcollections).
    final vehicleIdMap = <String, String>{};
    final fundIdMap = <String, String>{};

    for (final colKey in otherCollectionsOrder) {
      if (aborted) break;
      final rows =
          preview.collections[colKey] ?? const <Map<String, dynamic>>[];
      if (rows.isEmpty) continue;

      reportProgress(
        'Đang khôi phục ${BackupCollectionCatalog.labelFor(colKey).toLowerCase()}...',
      );

      final existingIds = await _loadExistingIdsForCollection(
        userId: targetUserId,
        colKey: colKey,
        vehicleIdMap: vehicleIdMap,
        fundIdMap: fundIdMap,
      );

      for (var i = 0; i < rows.length; i++) {
        if (aborted) break;
        final row = Map<String, dynamic>.from(rows[i]);
        final origId = (row['id'] ?? '').toString().trim();
        final targetId = mapDocId(colKey, origId, i);

        if (colKey == BackupCollectionCatalog.vehicles && origId.isNotEmpty) {
          vehicleIdMap[origId] = targetId;
        }
        if (colKey == BackupCollectionCatalog.personalFunds &&
            origId.isNotEmpty) {
          fundIdMap[origId] = targetId;
        }

        final compositeExistingKey = _compositeKeyForRow(
          colKey: colKey,
          row: row,
          targetDocId: targetId,
          vehicleIdMap: vehicleIdMap,
          fundIdMap: fundIdMap,
        );

        if (mode != BackupRestoreMode.replaceConfirmed &&
            existingIds.contains(compositeExistingKey)) {
          statsFor(colKey).skippedCount++;
          completedUnits++;
          continue;
        }

        // Validate budget limitMinor > 0 per firestore.rules
        if (colKey == BackupCollectionCatalog.budgets) {
          final limit = (row['limitMinor'] as num?)?.toInt() ?? 0;
          if (limit <= 0) {
            statsFor(colKey).failedCount++;
            failureMessages.add(
              'Ngân sách "${row['categoryName'] ?? targetId}" có hạn mức <= 0.',
            );
            completedUnits++;
            continue;
          }
        }

        try {
          writeIndex++;
          if (_onBeforeWrite != null) {
            await _onBeforeWrite(colKey, targetId, writeIndex);
          }

          await _writeGenericCollectionDoc(
            targetUserId: targetUserId,
            colKey: colKey,
            targetDocId: targetId,
            rawRow: row,
            resolveWalletId: resolveWalletId,
            vehicleIdMap: vehicleIdMap,
            fundIdMap: fundIdMap,
            overwriteExisting: mode == BackupRestoreMode.replaceConfirmed,
            lastRestoredSessionId: importSessionId,
          );
          existingIds.add(compositeExistingKey);
          statsFor(colKey).committedCount++;
        } catch (e) {
          aborted = true;
          failureMessages.add(
            'Gián đoạn khi ghi ${BackupCollectionCatalog.labelFor(colKey)} "$targetId": $e',
          );
        }
        completedUnits++;
      }
    }

    // Account for any remaining items not reached because an interruption aborted early!
    for (final stat in statsAcc.values) {
      final accounted =
          stat.committedCount + stat.skippedCount + stat.failedCount;
      if (accounted < stat.plannedCount) {
        stat.failedCount += (stat.plannedCount - accounted);
      }
    }

    // Step 3 (DATA-02): In `replaceConfirmed` mode, ONLY AFTER 100% of restore writes
    // succeed with ZERO errors, prune obsolete non-verified user-created records!
    // NEVER delete immutable verified bank transactions or wallets containing them!
    final canPruneAfterFullRestore =
        mode == BackupRestoreMode.replaceConfirmed &&
        !aborted &&
        failureMessages.isEmpty &&
        statsAcc.values.every((s) => s.failedCount == 0);

    if (canPruneAfterFullRestore) {
      await _pruneObsoleteRecordsAfterReplaceRestore(
        targetUserId: targetUserId,
        preview: preview,
        mapDocId: mapDocId,
        importSessionId: importSessionId,
        existingWallets: existingWallets,
        existingTxs: existingTxs,
        incomingWalletIdSet: incomingWalletIdSet,
        incomingTxIdSet: incomingTxIdSet,
        immutableVerifiedTxIds: immutableVerifiedTxIds,
        verifiedProtectedWalletIds: verifiedProtectedWalletIds,
        warnings: warnings,
      );
      await checkpointRef.set({
        'status': 'completed',
        'completedAt': Timestamp.fromDate(DateTime.now()),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      }, SetOptions(merge: true));
    } else if (mode == BackupRestoreMode.replaceConfirmed) {
      warnings.add(
        'Khôi phục chế độ Ghi đè bị gián đoạn trước khi hoàn tất — dữ liệu cũ được giữ nguyên an toàn.',
      );
      await checkpointRef.set({
        'status': 'aborted_before_prune',
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      }, SetOptions(merge: true));
    } else {
      await checkpointRef.set({
        'status': aborted ? 'partial' : 'completed',
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      }, SetOptions(merge: true));
    }

    // 9. Post-restore per-wallet balance verification against backup recorded balances!
    final postWalletsRes = await _transactionRepository
        .fetchAllWalletsPaginated(userId: targetUserId, pageSize: _pageSize);
    final postWalletsById = <String, WalletEntity>{
      if (postWalletsRes is Success<List<WalletEntity>>)
        for (final w in postWalletsRes.value) w.id: w,
    };

    final balanceChecks = <BackupWalletBalanceCheck>[];
    for (final w in incomingWallets) {
      if (!w.hasRecordedBalance) continue;
      final live = postWalletsById[w.targetId];
      final actualBal = live?.balanceMinor ?? 0;
      final matched = live != null && actualBal == w.recordedBalanceMinor;
      balanceChecks.add(
        BackupWalletBalanceCheck(
          walletId: w.targetId,
          walletName: live?.name ?? w.name,
          expectedBalanceMinor: w.recordedBalanceMinor,
          actualBalanceMinor: actualBal,
          matched: matched,
          isFromBackup: true,
        ),
      );
    }

    final perCollectionStats = statsAcc.values
        .map((s) => s.toEntity())
        .toList(growable: false);
    final committedTotal = perCollectionStats.fold<int>(
      0,
      (s, item) => s + item.committedCount,
    );
    final skippedTotal = perCollectionStats.fold<int>(
      0,
      (s, item) => s + item.skippedCount,
    );
    final failedTotal = perCollectionStats.fold<int>(
      0,
      (s, item) => s + item.failedCount,
    );
    final hasMismatches = balanceChecks.any((c) => !c.matched);

    final migratedCount = preview.schemaVersion < 3
        ? preview.totalRecordCount
        : 0;

    final detailsVi = <String>[];
    if (failedTotal == 0 && !hasMismatches) {
      detailsVi.add(
        'Đã ghi thành công $committedTotal bản ghi (${mode.labelVi.split('(').first.trim()}).',
      );
    } else if (failedTotal > 0) {
      detailsVi.add(
        'Khôi phục bị gián đoạn: đã ghi $committedTotal bản ghi, lỗi/chưa ghi $failedTotal bản ghi.',
      );
    } else {
      detailsVi.add(
        'Đã ghi $committedTotal bản ghi nhưng phát hiện lệch số dư ví — vui lòng kiểm tra chi tiết.',
      );
    }
    if (skippedTotal > 0) {
      detailsVi.add(
        'Đã bỏ qua $skippedTotal bản ghi đã tồn tại (tránh trùng lặp).',
      );
    }
    if (balanceChecks.isNotEmpty) {
      if (!hasMismatches) {
        detailsVi.add(
          'Đối soát số dư ${balanceChecks.length}/${balanceChecks.length} ví khớp 100% với bản sao lưu.',
        );
      } else {
        for (final mismatch in balanceChecks.where((b) => !b.matched)) {
          detailsVi.add(
            'Lệch ví "${mismatch.walletName}": sao lưu ${VndAmount.format(mismatch.expectedBalanceMinor)} vs thực tế ${VndAmount.format(mismatch.actualBalanceMinor)}.',
          );
        }
      }
    }
    if (failureMessages.isNotEmpty) {
      detailsVi.addAll(failureMessages.take(3));
    }

    return BackupRestoreExecutionReport(
      mode: mode,
      plannedCount: totalPlannedUnits,
      committedCount: committedTotal,
      skippedCount: skippedTotal,
      failedCount: failedTotal,
      migratedLegacyRecords: migratedCount,
      perCollectionStats: perCollectionStats,
      walletBalanceChecks: balanceChecks,
      failureMessages: failureMessages,
      warnings: warnings,
      detailsVi: detailsVi,
    );
  }

  Future<void> _pruneObsoleteRecordsAfterReplaceRestore({
    required String targetUserId,
    required BackupArchivePreview preview,
    required String Function(String colKey, String origId, int index) mapDocId,
    required String importSessionId,
    required List<WalletEntity> existingWallets,
    required List<TransactionEntity> existingTxs,
    required Set<String> incomingWalletIdSet,
    required Set<String> incomingTxIdSet,
    required Set<String> immutableVerifiedTxIds,
    required Set<String> verifiedProtectedWalletIds,
    required List<String> warnings,
  }) async {
    for (final colEntry in _firestoreCollectionByBackupKey.entries) {
      final colKey = colEntry.key;
      if (colKey == BackupCollectionCatalog.wallets ||
          colKey == BackupCollectionCatalog.transactions) {
        continue;
      }
      final incomingRows =
          preview.collections[colKey] ?? const <Map<String, dynamic>>[];
      final incomingIds = <String>{
        for (var i = 0; i < incomingRows.length; i++)
          mapDocId(colKey, (incomingRows[i]['id'] ?? '').toString(), i),
      };
      final existingDocs = await _fetchCollectionPaginated(
        _userCol(targetUserId, colEntry.value),
      );
      for (final doc in existingDocs) {
        if (incomingIds.contains(doc.id)) continue;
        if (doc.data()['lastRestoredSessionId'] == importSessionId) continue;

        if (colKey == BackupCollectionCatalog.vehicles) {
          for (final sub in const ['maintenances', 'fuel_logs']) {
            try {
              final subDocs = await _fetchCollectionPaginated(
                doc.reference.collection(sub),
              );
              for (final s in subDocs) {
                await s.reference.delete();
              }
            } catch (_) {}
          }
        } else if (colKey == BackupCollectionCatalog.personalFunds) {
          for (final sub in const [
            'contributions',
            'expenses',
            'fund_audits',
          ]) {
            try {
              final subDocs = await _fetchCollectionPaginated(
                doc.reference.collection(sub),
              );
              for (final s in subDocs) {
                await s.reference.delete();
              }
            } catch (_) {}
          }
        }
        try {
          await doc.reference.delete();
        } catch (_) {}
      }
    }

    for (final tx in existingTxs) {
      if (incomingTxIdSet.contains(tx.id)) continue;
      if (immutableVerifiedTxIds.contains(tx.id)) {
        warnings.add(
          'Đã giữ nguyên giao dịch ngân hàng xác thực "${tx.id}" (bất biến).',
        );
        continue;
      }
      try {
        await _userCol(targetUserId, 'transactions').doc(tx.id).delete();
      } catch (_) {
        warnings.add(
          'Không thể xóa giao dịch cũ "${tx.id}" do quy tắc sổ cái bất biến.',
        );
      }
    }

    for (final w in existingWallets) {
      if (incomingWalletIdSet.contains(w.id)) continue;
      if (verifiedProtectedWalletIds.contains(w.id)) {
        try {
          await _userCol(targetUserId, 'wallets').doc(w.id).update({
            'isArchived': true,
            'archivedByRestoreSessionId': importSessionId,
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          });
        } catch (_) {}
        warnings.add(
          'Đã giữ lại ví "${w.name}" (chuyển sang lưu trữ) vì còn giao dịch ngân hàng đã xác thực.',
        );
        continue;
      }
      try {
        await _userCol(targetUserId, 'wallets').doc(w.id).delete();
      } catch (_) {
        warnings.add('Không thể xóa ví cũ "${w.name}".');
      }
    }
  }

  Future<WalletEntity> _createMissingWalletDeterministic({
    required String userId,
    required _IncomingWalletSpec spec,
    required int openingBalanceMinor,
    String? lastRestoredSessionId,
  }) async {
    final docRef = _userCol(userId, 'wallets').doc(spec.targetId);
    final now = DateTime.now();
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (snap.exists) return;
      tx.set(docRef, {
        'id': spec.targetId,
        'ownerId': userId,
        'name': spec.name,
        'type': spec.type.name,
        'bankCode': spec.bankCode,
        'maskedAccount': spec.maskedAccount,
        'balanceMinor': openingBalanceMinor,
        if (spec.creditLimitMinor != null)
          'creditLimitMinor': spec.creditLimitMinor,
        'isEstimatedBalance': spec.isEstimatedBalance,
        if (lastRestoredSessionId != null)
          'lastRestoredSessionId': lastRestoredSessionId,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    });
    final snap = await docRef.get();
    return WalletModel.fromFirestore(snap).toEntity();
  }

  Future<void> _resetWalletBalanceWithAudit({
    required String userId,
    required WalletEntity wallet,
    required int targetBalanceMinor,
    required String operationTag,
    String? lastRestoredSessionId,
  }) async {
    final walletRef = _userCol(userId, 'wallets').doc(wallet.id);
    final auditId = 'aud_$operationTag';
    final auditRef = _userCol(userId, 'ledger_audits').doc(auditId);
    final now = DateTime.now();
    final ts = Timestamp.fromDate(now);

    await _firestore.runTransaction((tx) async {
      final wSnap = await tx.get(walletRef);
      if (!wSnap.exists) return;
      final currBal = (wSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
      if (currBal == targetBalanceMinor) return;
      final delta = targetBalanceMinor - currBal;
      final auditRes = LedgerIntegrityEngine.buildAndValidateAudit(
        auditId: auditId,
        operationId: operationTag,
        transactionId: operationTag,
        walletId: wallet.id,
        previousBalanceMinor: currBal,
        deltaAmountMinor: delta,
        newBalanceMinor: targetBalanceMinor,
        createdAt: now,
        actorId: userId,
        source: 'backup_restore_reset',
        verificationStatus: LedgerVerificationStatuses.userConfirmed,
        walletName: wallet.name,
        kind: 'adjustment',
      );
      if (auditRes is Err<LedgerAuditRecord>) {
        throw AppException(
          code: auditRes.failure.code,
          message: auditRes.failure.message,
        );
      }
      tx.set(
        auditRef,
        (auditRes as Success<LedgerAuditRecord>).value.toPayloadMap(
          createdAtValue: ts,
        ),
      );
      tx.update(walletRef, {
        'balanceMinor': targetBalanceMinor,
        'lastAuditId': auditId,
        if (lastRestoredSessionId != null)
          'lastRestoredSessionId': lastRestoredSessionId,
        'updatedAt': ts,
      });
    });
  }

  Future<TransactionEntity> _restoreNonReversalTransaction({
    required String targetUserId,
    required _IncomingTxSpec tx,
    String? lastRestoredSessionId,
  }) async {
    if (!tx.ledgerApplied) {
      // Provisional / needsReview / rejected transactions do NOT mutate wallet balance.
      final txRef = _userCol(targetUserId, 'transactions').doc(tx.targetId);
      final now = DateTime.now();
      await _firestore.runTransaction((fTx) async {
        final existing = await fTx.get(txRef);
        if (existing.exists) return;
        final payload = TransactionModel.toFirestoreMap(
          id: tx.targetId,
          operationId: tx.targetId,
          ownerId: targetUserId,
          walletId: tx.mappedWalletId,
          targetWalletId: tx.mappedTargetWalletId,
          categoryId: tx.categoryId,
          categoryName: tx.categoryName,
          kind: tx.kind,
          direction: tx.direction,
          amountMinor: tx.amountMinor,
          merchant: tx.merchant,
          note: tx.note,
          occurredAt: tx.occurredAt,
          sourceKind: tx.sourceKind,
          verification: tx.verification,
          verificationStatus:
              tx.verificationStatus ??
              LedgerVerificationStatuses.fromVerification(tx.verification),
          crossSourceFingerprint:
              tx.raw['crossSourceFingerprint']?.toString() ??
              'restore_${tx.targetId}',
          isVehicleMaintenanceHint: tx.isVehicleMaintenanceHint,
          isRefund: tx.isRefund,
          splitLines: tx.splitLines,
          balanceAfterMinor: tx.balanceAfterMinor,
          observedBalanceMinor: tx.observedBalanceMinor,
          walletName: tx.raw['walletName']?.toString(),
          now: now,
        );
        payload['ledgerApplied'] = false;
        if (lastRestoredSessionId != null) {
          payload['lastRestoredSessionId'] = lastRestoredSessionId;
        }
        fTx.set(txRef, payload);
      });
      final snap = await txRef.get();
      return TransactionModel.fromFirestore(snap).entity;
    }

    final validSplitLines =
        (tx.kind == TransactionKind.expense &&
            tx.splitLines.isNotEmpty &&
            tx.splitLines.fold<int>(0, (s, l) => s + l.amountMinor) ==
                tx.amountMinor)
        ? tx.splitLines
        : const <TransactionSplitLine>[];

    final res = await _createTransactionUseCase(
      CreateTransactionParams(
        operationId: tx.targetId,
        userId: targetUserId,
        walletId: tx.mappedWalletId,
        targetWalletId: tx.mappedTargetWalletId,
        categoryId: tx.categoryId,
        categoryName: tx.categoryName.trim().isEmpty
            ? 'Chi tiêu khác'
            : tx.categoryName.trim(),
        kind: tx.kind,
        amountMinor: tx.amountMinor,
        merchant: tx.merchant,
        note: tx.note,
        occurredAt: tx.occurredAt,
        splitLines: validSplitLines,
      ),
    );
    if (res is Err<TransactionEntity>) {
      throw AppException(code: res.failure.code, message: res.failure.message);
    }
    var created = (res as Success<TransactionEntity>).value;

    // Preserve extended verification / provenance / monthKey metadata when present.
    final rawMonthKey = tx.raw['monthKey']?.toString().trim();
    final needsMonthKeyRestore =
        rawMonthKey != null &&
        rawMonthKey.isNotEmpty &&
        rawMonthKey != created.monthKey;
    final needsMetadataMerge =
        needsMonthKeyRestore ||
        tx.isRefund ||
        tx.isRecurringCandidate ||
        tx.sourceKind != TransactionSourceKind.manual ||
        tx.verification == TransactionVerification.verified ||
        tx.verification == TransactionVerification.matchedPaymentOrder ||
        tx.referenceCode != null ||
        tx.observedBalanceMinor != null ||
        tx.bankCode != null ||
        tx.accountMasked != null ||
        tx.counterpartyDisplay != null ||
        tx.externalTransactionId != null ||
        tx.connectionId != null ||
        tx.sourceProvider != null ||
        tx.reconciliationStatus != null ||
        tx.sourceEventKey != null ||
        tx.receivedAt != null;

    if (needsMetadataMerge &&
        !LedgerIntegrityEngine.isImmutableVerified(created)) {
      final txRef = _userCol(targetUserId, 'transactions').doc(tx.targetId);
      final updates = <String, dynamic>{
        if (needsMonthKeyRestore) 'monthKey': rawMonthKey,
        'sourceKind': tx.sourceKind.name,
        'verification': tx.verification.name,
        'verificationStatus':
            tx.verificationStatus ??
            LedgerVerificationStatuses.fromVerification(tx.verification),
        if (tx.isRefund) 'isRefund': true,
        if (tx.isRecurringCandidate) 'isRecurringCandidate': true,
        if (tx.referenceCode != null) 'referenceCode': tx.referenceCode,
        if (tx.observedBalanceMinor != null)
          'observedBalanceMinor': tx.observedBalanceMinor,
        if (tx.observedBalanceMinor != null && tx.observedBalanceMinor! > 0)
          'balanceType': TransactionBalanceType.observedBankBalance.name,
        if (tx.bankCode != null) 'bankCode': tx.bankCode,
        if (tx.accountMasked != null) 'accountMasked': tx.accountMasked,
        if (tx.counterpartyDisplay != null)
          'counterpartyDisplay': tx.counterpartyDisplay,
        if (tx.externalTransactionId != null)
          'externalTransactionId': tx.externalTransactionId,
        if (tx.connectionId != null) 'connectionId': tx.connectionId,
        if (tx.sourceProvider != null) 'sourceProvider': tx.sourceProvider,
        if (tx.reconciliationStatus != null)
          'reconciliationStatus': tx.reconciliationStatus,
        if (tx.sourceEventKey != null) 'sourceEventKey': tx.sourceEventKey,
        if (tx.receivedAt != null)
          'receivedAt': Timestamp.fromDate(tx.receivedAt!),
      };
      await txRef.update(updates);
      final refreshed = await txRef.get();
      created = TransactionModel.fromFirestore(refreshed).entity;
    }

    return created;
  }

  Future<TransactionEntity> _restoreReversalTransaction({
    required String targetUserId,
    required _IncomingTxSpec rev,
    required Map<String, TransactionEntity> existingTxById,
  }) async {
    final origId = rev.mappedReversalOfId;
    final origExisting = origId != null ? existingTxById[origId] : null;
    final canUseCanonicalReversal =
        origId != null &&
        origExisting != null &&
        !origExisting.isReversed &&
        origExisting.kind != TransactionKind.reversal &&
        origExisting.isConfirmedInLedger &&
        rev.targetId == 'rev_$origId';

    if (canUseCanonicalReversal) {
      final res = await _reverseTransactionUseCase(
        ReverseTransactionParams(
          userId: targetUserId,
          transactionId: origId,
          reason: (rev.note != null && rev.note!.trim().isNotEmpty)
              ? rev.note!.trim()
              : (rev.merchant.trim().isNotEmpty
                    ? rev.merchant.trim()
                    : 'Hoàn tiền / Đảo bút toán'),
        ),
      );
      if (res is Err<TransactionEntity>) {
        throw AppException(
          code: res.failure.code,
          message: res.failure.message,
        );
      }
      existingTxById[origId] = TransactionEntity(
        id: origExisting.id,
        ownerId: origExisting.ownerId,
        walletId: origExisting.walletId,
        targetWalletId: origExisting.targetWalletId,
        categoryId: origExisting.categoryId,
        categoryName: origExisting.categoryName,
        kind: origExisting.kind,
        direction: origExisting.direction,
        amountMinor: origExisting.amountMinor,
        currencyCode: origExisting.currencyCode,
        merchant: origExisting.merchant,
        note: origExisting.note,
        occurredAt: origExisting.occurredAt,
        monthKey: origExisting.monthKey,
        sourceKind: origExisting.sourceKind,
        verification: origExisting.verification,
        crossSourceFingerprint: origExisting.crossSourceFingerprint,
        reversalOfId: origExisting.reversalOfId,
        reversedById: rev.targetId,
        isVehicleMaintenanceHint: origExisting.isVehicleMaintenanceHint,
        splitLines: origExisting.splitLines,
        balanceAfterMinor: origExisting.balanceAfterMinor,
        balanceType: origExisting.balanceType,
        ledgerApplied: origExisting.ledgerApplied,
        walletName: origExisting.walletName,
        verificationStatus: LedgerVerificationStatuses.reversed,
      );

      // Preserve the backup's historical occurredAt / monthKey / merchant on the reversal record.
      final revRef = _userCol(targetUserId, 'transactions').doc(rev.targetId);
      final rawRevMonthKey = rev.raw['monthKey']?.toString().trim();
      final monthKey = (rawRevMonthKey != null && rawRevMonthKey.isNotEmpty)
          ? rawRevMonthKey
          : '${rev.occurredAt.year.toString().padLeft(4, '0')}-${rev.occurredAt.month.toString().padLeft(2, '0')}';
      await revRef.update({
        'occurredAt': Timestamp.fromDate(rev.occurredAt),
        'monthKey': monthKey,
        if (rev.merchant.trim().isNotEmpty) 'merchant': rev.merchant.trim(),
      });
      final refreshed = await revRef.get();
      return TransactionModel.fromFirestore(refreshed).entity;
    }

    // Fallback atomic reversal for orphan reversals or non-canonical reversal doc IDs.
    final revRef = _userCol(targetUserId, 'transactions').doc(rev.targetId);
    final srcWalletRef = _userCol(
      targetUserId,
      'wallets',
    ).doc(rev.mappedWalletId);
    final targetWalletRef =
        (rev.mappedTargetWalletId != null &&
            rev.mappedTargetWalletId!.isNotEmpty)
        ? _userCol(targetUserId, 'wallets').doc(rev.mappedTargetWalletId)
        : null;
    final origRef = origId != null
        ? _userCol(targetUserId, 'transactions').doc(origId)
        : null;

    await _firestore.runTransaction((fTx) async {
      final existingRev = await fTx.get(revRef);
      if (existingRev.exists) return;

      final srcSnap = await fTx.get(srcWalletRef);
      if (!srcSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy ví nguồn cho bút toán đảo.',
        );
      }
      final srcBal = (srcSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
      final srcName = srcSnap.data()?['name']?.toString() ?? 'Ví nguồn';
      final now = DateTime.now();
      final tsNow = Timestamp.fromDate(now);

      final isTransferRev = targetWalletRef != null;
      final srcDelta = isTransferRev
          ? rev.amountMinor
          : (rev.direction == 'credit' ? rev.amountMinor : -rev.amountMinor);
      final newSrcBal = srcBal + srcDelta;
      final srcAuditId = 'aud_${rev.targetId}_src';
      final srcAudit = LedgerIntegrityEngine.buildAndValidateAudit(
        auditId: srcAuditId,
        operationId: rev.targetId,
        transactionId: rev.targetId,
        walletId: rev.mappedWalletId,
        previousBalanceMinor: srcBal,
        deltaAmountMinor: srcDelta,
        newBalanceMinor: newSrcBal,
        createdAt: now,
        actorId: targetUserId,
        source: 'backup_restore_reversal',
        verificationStatus: LedgerVerificationStatuses.userConfirmed,
        walletName: srcName,
        kind: TransactionKind.reversal.name,
      );
      if (srcAudit is Err<LedgerAuditRecord>) {
        throw AppException(
          code: srcAudit.failure.code,
          message: srcAudit.failure.message,
        );
      }

      DocumentSnapshot<Map<String, dynamic>>? dstSnap;
      if (targetWalletRef != null) {
        dstSnap = await fTx.get(targetWalletRef);
      }
      DocumentSnapshot<Map<String, dynamic>>? origSnap;
      if (origRef != null) {
        origSnap = await fTx.get(origRef);
      }

      fTx.update(srcWalletRef, {
        'balanceMinor': newSrcBal,
        'lastAuditId': srcAuditId,
        'updatedAt': tsNow,
      });
      fTx.set(
        _userCol(targetUserId, 'ledger_audits').doc(srcAuditId),
        (srcAudit as Success<LedgerAuditRecord>).value.toPayloadMap(
          createdAtValue: tsNow,
        ),
      );

      if (targetWalletRef != null && dstSnap != null && dstSnap.exists) {
        final dstBal = (dstSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
        final dstName = dstSnap.data()?['name']?.toString() ?? 'Ví đích';
        final newDstBal = dstBal - rev.amountMinor;
        final dstAuditId = 'aud_${rev.targetId}_dst';
        final dstAudit = LedgerIntegrityEngine.buildAndValidateAudit(
          auditId: dstAuditId,
          operationId: rev.targetId,
          transactionId: rev.targetId,
          walletId: rev.mappedTargetWalletId!,
          previousBalanceMinor: dstBal,
          deltaAmountMinor: -rev.amountMinor,
          newBalanceMinor: newDstBal,
          createdAt: now,
          actorId: targetUserId,
          source: 'backup_restore_reversal',
          verificationStatus: LedgerVerificationStatuses.userConfirmed,
          walletName: dstName,
          kind: TransactionKind.reversal.name,
        );
        if (dstAudit is Err<LedgerAuditRecord>) {
          throw AppException(
            code: dstAudit.failure.code,
            message: dstAudit.failure.message,
          );
        }
        fTx.update(targetWalletRef, {
          'balanceMinor': newDstBal,
          'lastAuditId': dstAuditId,
          'updatedAt': tsNow,
        });
        fTx.set(
          _userCol(targetUserId, 'ledger_audits').doc(dstAuditId),
          (dstAudit as Success<LedgerAuditRecord>).value.toPayloadMap(
            createdAtValue: tsNow,
          ),
        );
      }

      if (origRef != null && origSnap != null && origSnap.exists) {
        fTx.update(origRef, {
          'reversedById': rev.targetId,
          'verificationStatus': LedgerVerificationStatuses.reversed,
          'updatedAt': tsNow,
        });
      }

      fTx.set(
        revRef,
        TransactionModel.toFirestoreMap(
          id: rev.targetId,
          operationId: rev.targetId,
          ownerId: targetUserId,
          walletId: rev.mappedWalletId,
          targetWalletId: rev.mappedTargetWalletId,
          categoryId: rev.categoryId,
          categoryName: rev.categoryName,
          kind: TransactionKind.reversal,
          direction: rev.direction,
          amountMinor: rev.amountMinor,
          merchant: rev.merchant.isEmpty ? '[Đảo bút toán]' : rev.merchant,
          note: rev.note,
          occurredAt: rev.occurredAt,
          sourceKind: rev.sourceKind,
          verification: TransactionVerification.userConfirmed,
          verificationStatus: LedgerVerificationStatuses.userConfirmed,
          crossSourceFingerprint:
              rev.raw['crossSourceFingerprint']?.toString() ??
              'rev_${rev.targetId}',
          reversalOfId: origId,
          balanceAfterMinor: newSrcBal,
          walletName: srcName,
          now: now,
        ),
      );
    });

    final snap = await revRef.get();
    return TransactionModel.fromFirestore(snap).entity;
  }

  Future<Set<String>> _loadExistingIdsForCollection({
    required String userId,
    required String colKey,
    required Map<String, String> vehicleIdMap,
    required Map<String, String> fundIdMap,
  }) async {
    if (colKey == BackupCollectionCatalog.vehicleMaintenances) {
      final ids = <String>{};
      final vehiclesSnap = await _fetchCollectionPaginated(
        _userCol(userId, 'vehicles'),
      );
      for (final vDoc in vehiclesSnap) {
        final mDocs = await _fetchCollectionPaginated(
          vDoc.reference.collection('maintenances'),
        );
        for (final m in mDocs) {
          ids.add('${vDoc.id}::${m.id}');
        }
      }
      return ids;
    }

    if (colKey == BackupCollectionCatalog.fundContributions ||
        colKey == BackupCollectionCatalog.fundExpenses ||
        colKey == BackupCollectionCatalog.fundAudits) {
      final subName = switch (colKey) {
        BackupCollectionCatalog.fundContributions => 'contributions',
        BackupCollectionCatalog.fundExpenses => 'expenses',
        _ => 'fund_audits',
      };
      final ids = <String>{};
      final fSnap = await _fetchCollectionPaginated(
        _userCol(userId, 'personal_funds'),
      );
      for (final fDoc in fSnap) {
        final subDocs = await _fetchCollectionPaginated(
          fDoc.reference.collection(subName),
        );
        for (final sd in subDocs) {
          ids.add('${fDoc.id}::${sd.id}');
        }
      }
      return ids;
    }

    final colName = _firestoreCollectionByBackupKey[colKey];
    if (colName == null) return <String>{};
    final docs = await _fetchCollectionPaginated(_userCol(userId, colName));
    return <String>{for (final d in docs) d.id};
  }

  String _compositeKeyForRow({
    required String colKey,
    required Map<String, dynamic> row,
    required String targetDocId,
    required Map<String, String> vehicleIdMap,
    required Map<String, String> fundIdMap,
  }) {
    if (colKey == BackupCollectionCatalog.vehicleMaintenances) {
      final origVeh = (row['vehicleId'] ?? '').toString().trim();
      final mappedVeh = vehicleIdMap[origVeh] ?? origVeh;
      return '$mappedVeh::$targetDocId';
    }
    if (colKey == BackupCollectionCatalog.fundContributions ||
        colKey == BackupCollectionCatalog.fundExpenses ||
        colKey == BackupCollectionCatalog.fundAudits) {
      final origFund = (row['fundId'] ?? '').toString().trim();
      final mappedFund = fundIdMap[origFund] ?? origFund;
      return '$mappedFund::$targetDocId';
    }
    return targetDocId;
  }

  Future<void> _writeGenericCollectionDoc({
    required String targetUserId,
    required String colKey,
    required String targetDocId,
    required Map<String, dynamic> rawRow,
    required String Function(String? origWalletId) resolveWalletId,
    required Map<String, String> vehicleIdMap,
    required Map<String, String> fundIdMap,
    bool overwriteExisting = false,
    String? lastRestoredSessionId,
  }) async {
    late final DocumentReference<Map<String, dynamic>> docRef;
    if (colKey == BackupCollectionCatalog.vehicleMaintenances) {
      final origVeh = (rawRow['vehicleId'] ?? '').toString().trim();
      final mappedVeh = vehicleIdMap[origVeh] ?? origVeh;
      if (mappedVeh.isEmpty) {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message: 'Bản ghi bảo dưỡng thiếu vehicleId.',
        );
      }
      docRef = _userCol(
        targetUserId,
        'vehicles',
      ).doc(mappedVeh).collection('maintenances').doc(targetDocId);
    } else if (colKey == BackupCollectionCatalog.fundContributions ||
        colKey == BackupCollectionCatalog.fundExpenses ||
        colKey == BackupCollectionCatalog.fundAudits) {
      final origFund = (rawRow['fundId'] ?? '').toString().trim();
      final mappedFund = fundIdMap[origFund] ?? origFund;
      if (mappedFund.isEmpty) {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message: 'Bản ghi quỹ thiếu fundId.',
        );
      }
      final subName = switch (colKey) {
        BackupCollectionCatalog.fundContributions => 'contributions',
        BackupCollectionCatalog.fundExpenses => 'expenses',
        _ => 'fund_audits',
      };
      docRef = _userCol(
        targetUserId,
        'personal_funds',
      ).doc(mappedFund).collection(subName).doc(targetDocId);
    } else {
      final colName = _firestoreCollectionByBackupKey[colKey];
      if (colName == null) return;
      docRef = _userCol(targetUserId, colName).doc(targetDocId);
    }

    final payload = _prepareFirestorePayload(
      colKey: colKey,
      targetUserId: targetUserId,
      targetDocId: targetDocId,
      rawRow: rawRow,
      resolveWalletId: resolveWalletId,
      vehicleIdMap: vehicleIdMap,
      fundIdMap: fundIdMap,
    );
    if (lastRestoredSessionId != null) {
      payload['lastRestoredSessionId'] = lastRestoredSessionId;
    }

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (snap.exists && !overwriteExisting) return;
      tx.set(docRef, payload);
    });
  }

  Map<String, dynamic> _prepareFirestorePayload({
    required String colKey,
    required String targetUserId,
    required String targetDocId,
    required Map<String, dynamic> rawRow,
    required String Function(String? origWalletId) resolveWalletId,
    required Map<String, String> vehicleIdMap,
    required Map<String, String> fundIdMap,
  }) {
    final tsFields = <String>{
      ...?_defaultTimestampFields[colKey],
      if (rawRow['__tsFields'] is List)
        for (final f in rawRow['__tsFields'] as List) f.toString(),
    };

    final payload = <String, dynamic>{};
    for (final entry in rawRow.entries) {
      if (entry.key == '__tsFields') continue;
      final val = entry.value;
      if (tsFields.contains(entry.key) && val is String && val.isNotEmpty) {
        final dt = DateTime.tryParse(val);
        if (dt != null) {
          payload[entry.key] = Timestamp.fromDate(dt);
          continue;
        }
      }
      payload[entry.key] = val;
    }

    // Rebind identity & deterministic IDs cleanly per collection schema.
    payload['id'] = targetDocId;

    switch (colKey) {
      case BackupCollectionCatalog.tasks:
        payload['createdBy'] = targetUserId;
        payload['assigneeId'] = targetUserId;
        payload['familyId'] = null;
        payload.putIfAbsent('creatorName', () => 'Cá nhân');
        payload.putIfAbsent('assigneeName', () => 'Cá nhân');
        payload.putIfAbsent('priority', () => 'medium');
        payload.putIfAbsent('status', () => 'accepted');
        payload.putIfAbsent('recurrence', () => 'none');
        payload.putIfAbsent(
          'createdAt',
          () => Timestamp.fromDate(DateTime.now()),
        );
        payload.putIfAbsent(
          'updatedAt',
          () => Timestamp.fromDate(DateTime.now()),
        );
      case BackupCollectionCatalog.events:
        payload['ownerId'] = targetUserId;
        payload['familyId'] = null;
        payload['visibility'] = 'privateEvent';
        payload.putIfAbsent('calendarId', () => 'primary');
        payload.putIfAbsent('ownerName', () => 'Cá nhân');
        payload.putIfAbsent('syncStatus', () => 'localOnly');
        payload.putIfAbsent(
          'startsAt',
          () => Timestamp.fromDate(DateTime.now()),
        );
        payload.putIfAbsent('endsAt', () => Timestamp.fromDate(DateTime.now()));
        payload.putIfAbsent(
          'updatedAt',
          () => Timestamp.fromDate(DateTime.now()),
        );
      case BackupCollectionCatalog.vehicles:
        payload['ownerId'] = targetUserId;
        payload.remove('familyId');
        payload.putIfAbsent(
          'lastServiceDate',
          () => Timestamp.fromDate(DateTime.now()),
        );
      case BackupCollectionCatalog.vehicleMaintenances:
        final origVeh = (rawRow['vehicleId'] ?? '').toString().trim();
        payload['vehicleId'] = vehicleIdMap[origVeh] ?? origVeh;
      case BackupCollectionCatalog.bills:
        payload['ownerId'] = targetUserId;
        payload.remove('familyId');
        payload.putIfAbsent(
          'nextDueDate',
          () => Timestamp.fromDate(DateTime.now()),
        );
      case BackupCollectionCatalog.personalFunds:
        payload['ownerId'] = targetUserId;
        payload['familyId'] = null;
        payload['scope'] = 'personal';
      case BackupCollectionCatalog.fundContributions:
        final origFund = (rawRow['fundId'] ?? '').toString().trim();
        payload['fundId'] = fundIdMap[origFund] ?? origFund;
        payload['contributorId'] = targetUserId;
        if (payload['sourceWalletId'] != null &&
            payload['sourceWalletId'].toString().trim().isNotEmpty) {
          payload['sourceWalletId'] = resolveWalletId(
            payload['sourceWalletId'].toString(),
          );
        }
      case BackupCollectionCatalog.fundExpenses:
        final origFund = (rawRow['fundId'] ?? '').toString().trim();
        payload['fundId'] = fundIdMap[origFund] ?? origFund;
        payload['requesterId'] = targetUserId;
      case BackupCollectionCatalog.fundAudits:
        final origFund = (rawRow['fundId'] ?? '').toString().trim();
        payload['fundId'] = fundIdMap[origFund] ?? origFund;
        payload['actorId'] = targetUserId;
      case BackupCollectionCatalog.bankAccounts:
        payload['ownerId'] = targetUserId;
        if (payload['walletId'] != null) {
          payload['walletId'] = resolveWalletId(payload['walletId'].toString());
        }
      case BackupCollectionCatalog.aiPersonalizationRules:
        payload['userId'] = targetUserId;
        payload['ownerId'] = targetUserId;
        if (payload['preferredWalletId'] != null) {
          payload['preferredWalletId'] = resolveWalletId(
            payload['preferredWalletId'].toString(),
          );
        }
      case BackupCollectionCatalog.documents:
        payload['ownerId'] = targetUserId;
        payload['uploadedBy'] = targetUserId;
        payload['familyId'] = null;
        payload['isFamilyShared'] = false;
        payload.remove('localAttachmentPath');
      case BackupCollectionCatalog.notes:
        payload['ownerId'] = targetUserId;
        payload.putIfAbsent(
          'updatedAt',
          () => DateTime.now().toUtc().toIso8601String(),
        );
      case BackupCollectionCatalog.wellnessDaily:
        payload.remove('id');
        payload['dateKey'] = targetDocId;
        payload['ownerId'] = targetUserId;
      case BackupCollectionCatalog.mealPlans:
        payload.remove('id');
        payload['ownerId'] = targetUserId;
      case BackupCollectionCatalog.automationRules:
        payload['ownerId'] = targetUserId;
      default:
        payload['ownerId'] = targetUserId;
    }

    return payload;
  }

  Map<String, dynamic> _walletEntityToMap(WalletEntity w) {
    return <String, dynamic>{
      'id': w.id,
      'ownerId': w.ownerId,
      'name': w.name,
      'type': w.type.name,
      if (w.bankCode != null) 'bankCode': w.bankCode,
      if (w.maskedAccount != null) 'maskedAccount': w.maskedAccount,
      'balanceMinor': w.balanceMinor,
      if (w.creditLimitMinor != null) 'creditLimitMinor': w.creditLimitMinor,
      'isEstimatedBalance': w.isEstimatedBalance,
      if (w.lastAuditId != null) 'lastAuditId': w.lastAuditId,
    };
  }

  Map<String, dynamic> _categoryEntityToMap(CategoryEntity c) {
    return <String, dynamic>{
      'id': c.id,
      'ownerId': c.ownerId,
      'name': c.name,
      'direction': c.direction,
      'iconKey': c.iconKey,
    };
  }

  Map<String, dynamic> _transactionEntityToMap(TransactionEntity t) {
    return <String, dynamic>{
      'id': t.id,
      if (t.operationId != null) 'operationId': t.operationId,
      'ownerId': t.ownerId,
      'walletId': t.walletId,
      if (t.targetWalletId != null) 'targetWalletId': t.targetWalletId,
      if (t.categoryId != null) 'categoryId': t.categoryId,
      'categoryName': t.categoryName,
      'kind': t.kind.name,
      'direction': t.direction,
      'amountMinor': t.amountMinor,
      'currencyCode': t.currencyCode,
      'merchant': t.merchant,
      if (t.note != null) 'note': t.note,
      'occurredAt': t.occurredAt.toUtc().toIso8601String(),
      'monthKey': t.monthKey,
      'sourceKind': t.sourceKind.name,
      'verification': t.verification.name,
      if (t.verificationStatus != null)
        'verificationStatus': t.verificationStatus,
      'crossSourceFingerprint': t.crossSourceFingerprint,
      if (t.reversalOfId != null) 'reversalOfId': t.reversalOfId,
      if (t.reversedById != null) 'reversedById': t.reversedById,
      if (t.isVehicleMaintenanceHint) 'isVehicleMaintenanceHint': true,
      if (t.isRefund) 'isRefund': true,
      if (t.isRecurringCandidate) 'isRecurringCandidate': true,
      if (t.splitLines.isNotEmpty)
        'splitLines': t.splitLines
            .map(
              (s) => <String, dynamic>{
                'categoryName': s.categoryName,
                'amountMinor': s.amountMinor,
                if (s.note != null && s.note!.isNotEmpty) 'note': s.note,
              },
            )
            .toList(),
      if (t.balanceAfterMinor != null) 'balanceAfterMinor': t.balanceAfterMinor,
      if (t.observedBalanceMinor != null)
        'observedBalanceMinor': t.observedBalanceMinor,
      'balanceType': t.balanceType.name,
      'ledgerApplied': t.ledgerApplied,
      if (t.walletName != null) 'walletName': t.walletName,
      if (t.connectionId != null) 'connectionId': t.connectionId,
      if (t.sourceProvider != null) 'sourceProvider': t.sourceProvider,
      if (t.externalTransactionId != null)
        'externalTransactionId': t.externalTransactionId,
      if (t.referenceCode != null) 'referenceCode': t.referenceCode,
      if (t.bankCode != null) 'bankCode': t.bankCode,
      if (t.accountMasked != null) 'accountMasked': t.accountMasked,
      if (t.counterpartyDisplay != null)
        'counterpartyDisplay': t.counterpartyDisplay,
      if (t.receivedAt != null)
        'receivedAt': t.receivedAt!.toUtc().toIso8601String(),
      if (t.reconciliationStatus != null)
        'reconciliationStatus': t.reconciliationStatus,
      if (t.sourceEventKey != null) 'sourceEventKey': t.sourceEventKey,
    };
  }

  Map<String, dynamic> _sanitizeFirestoreDoc(
    String docId,
    Map<String, dynamic> data,
  ) {
    final tsFields = <String>[];
    final out = <String, dynamic>{'id': docId};
    for (final entry in data.entries) {
      final val = entry.value;
      if (val is Timestamp) {
        tsFields.add(entry.key);
        out[entry.key] = val.toDate().toUtc().toIso8601String();
      } else {
        out[entry.key] = _sanitizeNestedValue(val);
      }
    }
    if (tsFields.isNotEmpty) {
      out['__tsFields'] = tsFields;
    }
    return out;
  }

  dynamic _sanitizeNestedValue(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toUtc().toIso8601String();
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _sanitizeNestedValue(entry.value),
      };
    }
    if (value is List) {
      return value.map(_sanitizeNestedValue).toList();
    }
    return value;
  }

  static WalletType _parseWalletType(String raw) => switch (raw) {
    'bank' => WalletType.bank,
    'creditCard' || 'credit_card' => WalletType.creditCard,
    'savings' || 'investment' => WalletType.savings,
    _ => WalletType.cash,
  };

  static TransactionKind _parseTransactionKind(String raw) => switch (raw) {
    'income' => TransactionKind.income,
    'transfer' => TransactionKind.transfer,
    'creditCardPayment' => TransactionKind.creditCardPayment,
    'reversal' => TransactionKind.reversal,
    _ => TransactionKind.expense,
  };

  static TransactionVerification _parseVerification(String? raw) =>
      switch (raw) {
        'provisional' => TransactionVerification.provisional,
        'matchedPaymentOrder' => TransactionVerification.matchedPaymentOrder,
        'verified' => TransactionVerification.verified,
        'rejected' => TransactionVerification.rejected,
        'needsReview' => TransactionVerification.needsReview,
        _ => TransactionVerification.userConfirmed,
      };

  static TransactionSourceKind _parseSourceKind(String? raw) => switch (raw) {
    'androidNotification' => TransactionSourceKind.androidNotification,
    'csv' => TransactionSourceKind.csv,
    'bankApi' => TransactionSourceKind.bankApi,
    'bankWebhook' => TransactionSourceKind.bankWebhook,
    _ => TransactionSourceKind.manual,
  };

  static String _resolveDirection({
    required TransactionKind kind,
    String? rawDirection,
  }) {
    if (rawDirection == 'credit' || rawDirection == 'debit') {
      return rawDirection!;
    }
    return kind == TransactionKind.income ? 'credit' : 'debit';
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw is Timestamp) return raw.toDate().toUtc();
    if (raw is DateTime) return raw.toUtc();
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim())?.toUtc();
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    }
    return null;
  }

  static List<TransactionSplitLine> _parseSplitLines(Object? raw) {
    if (raw is! List) return const <TransactionSplitLine>[];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (item) => TransactionSplitLine(
            categoryName: (item['categoryName'] ?? 'Chi tiêu khác').toString(),
            amountMinor: (item['amountMinor'] as num?)?.toInt() ?? 0,
            note: item['note']?.toString(),
          ),
        )
        .where((l) => l.amountMinor > 0)
        .toList(growable: false);
  }
}

class _IncomingWalletSpec {
  final String origId;
  final String targetId;
  final String name;
  final WalletType type;
  final int recordedBalanceMinor;
  final bool hasRecordedBalance;
  final String? bankCode;
  final String? maskedAccount;
  final int? creditLimitMinor;
  final bool isEstimatedBalance;
  final Map<String, dynamic> raw;

  const _IncomingWalletSpec({
    required this.origId,
    required this.targetId,
    required this.name,
    required this.type,
    required this.recordedBalanceMinor,
    required this.hasRecordedBalance,
    this.bankCode,
    this.maskedAccount,
    this.creditLimitMinor,
    this.isEstimatedBalance = true,
    required this.raw,
  });
}

class _IncomingTxSpec {
  final String origId;
  final String targetId;
  final String mappedWalletId;
  final String? mappedTargetWalletId;
  final String? mappedReversalOfId;
  final String? categoryId;
  final String categoryName;
  final TransactionKind kind;
  final String direction;
  final int amountMinor;
  final String merchant;
  final String? note;
  final DateTime occurredAt;
  final TransactionSourceKind sourceKind;
  final TransactionVerification verification;
  final String? verificationStatus;
  final bool isRefund;
  final bool isVehicleMaintenanceHint;
  final bool isRecurringCandidate;
  final List<TransactionSplitLine> splitLines;
  final int? balanceAfterMinor;
  final int? observedBalanceMinor;
  final String? referenceCode;
  final String? bankCode;
  final String? accountMasked;
  final String? counterpartyDisplay;
  final String? externalTransactionId;
  final String? connectionId;
  final String? sourceProvider;
  final String? reconciliationStatus;
  final String? sourceEventKey;
  final DateTime? receivedAt;
  final bool ledgerApplied;
  final Map<String, dynamic> raw;

  const _IncomingTxSpec({
    required this.origId,
    required this.targetId,
    required this.mappedWalletId,
    this.mappedTargetWalletId,
    this.mappedReversalOfId,
    this.categoryId,
    required this.categoryName,
    required this.kind,
    required this.direction,
    required this.amountMinor,
    required this.merchant,
    this.note,
    required this.occurredAt,
    required this.sourceKind,
    required this.verification,
    this.verificationStatus,
    this.isRefund = false,
    this.isVehicleMaintenanceHint = false,
    this.isRecurringCandidate = false,
    this.splitLines = const <TransactionSplitLine>[],
    this.balanceAfterMinor,
    this.observedBalanceMinor,
    this.referenceCode,
    this.bankCode,
    this.accountMasked,
    this.counterpartyDisplay,
    this.externalTransactionId,
    this.connectionId,
    this.sourceProvider,
    this.reconciliationStatus,
    this.sourceEventKey,
    this.receivedAt,
    required this.ledgerApplied,
    required this.raw,
  });

  bool get isConfirmedInLedger => ledgerApplied;
}

class _MutableStats {
  final String colKey;
  final String labelVi;
  int plannedCount = 0;
  int committedCount = 0;
  int skippedCount = 0;
  int failedCount = 0;

  _MutableStats(this.colKey, this.labelVi);

  BackupCollectionCommitStats toEntity() => BackupCollectionCommitStats(
    collectionKey: colKey,
    labelVi: labelVi,
    plannedCount: plannedCount,
    committedCount: committedCount,
    skippedCount: skippedCount,
    failedCount: failedCount,
  );
}
