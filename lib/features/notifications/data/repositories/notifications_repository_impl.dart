import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/services/android_notification_bridge.dart';
import '../../../../core/services/native_alarm_scheduler_bridge.dart';
import '../../../../core/services/native_secure_vault_bridge.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../domain/entities/notification_entities.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../datasources/sepay_api_datasource.dart';

class NotificationsRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;
  final AndroidNotificationBridge _bridge;
  final SePayApiDataSource _sePayApi;

  NotificationsRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseAuth firebaseAuth,
    required AndroidNotificationBridge bridge,
    SePayApiDataSource? sePayApi,
  })  : _firestore = firestore,
        _firebaseAuth = firebaseAuth,
        _bridge = bridge,
        _sePayApi = sePayApi ?? SePayApiDataSource();

  Future<bool> isNativePermissionGranted() => _bridge.isNotificationAccessGranted();

  Future<void> openNativePermissionSettings() => _bridge.openNotificationAccessSettings();

  Stream<Map<String, dynamic>> watchLiveNativeSignals() =>
      _bridge.watchIncomingBankNotifications();

  Future<List<Map<String, dynamic>>> drainQueuedNativeSignals() =>
      _bridge.drainQueuedBackgroundNotifications();

  DocumentReference<Map<String, dynamic>> _sePayConfigRef(String userId) =>
      _firestore.collection('users').doc(userId).collection('consents').doc('sepay_api');

  static String _sePayVaultKey(String userId) => 'sepay_api_token_$userId';

  static String _maskSecretToken(String token) {
    final t = token.trim();
    if (t.isEmpty) return '';
    if (t.length <= 6) return '••••••';
    return '••••••••••••${t.substring(t.length - 4)}';
  }

  Future<String?> getSavedSePayMaskedToken(String userId) async {
    final vaultToken = await NativeSecureVaultBridge.instance.readSecret(_sePayVaultKey(userId));
    if (vaultToken != null && vaultToken.trim().isNotEmpty) {
      return _maskSecretToken(vaultToken);
    }
    final snap = await _sePayConfigRef(userId).get();
    if (!snap.exists) return null;
    final data = snap.data() ?? const <String, dynamic>{};
    // Auto-migrate & scrub any legacy plaintext `apiToken` stored by older app versions
    final legacyPlain = (data['apiToken'] as String?)?.trim() ?? '';
    if (legacyPlain.isNotEmpty) {
      await NativeSecureVaultBridge.instance.writeSecret(
        key: _sePayVaultKey(userId),
        value: legacyPlain,
      );
      final masked = _maskSecretToken(legacyPlain);
      await _sePayConfigRef(userId).set(
        {
          'sourceId': 'sepay_api',
          'ownerId': userId,
          'hasTokenConfigured': true,
          'maskedToken': masked,
          'apiToken': FieldValue.delete(),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        },
        SetOptions(merge: true),
      );
      return masked;
    }
    final savedMasked = (data['maskedToken'] as String?)?.trim() ?? '';
    return savedMasked.isEmpty ? null : savedMasked;
  }

  Future<int> syncSePayTransactions({
    required String userId,
    required String walletId,
    String? apiTokenOverride,
    int limit = 40,
  }) async {
    var resolvedToken = apiTokenOverride?.trim() ?? '';
    if (resolvedToken.isNotEmpty) {
      await NativeSecureVaultBridge.instance.writeSecret(
        key: _sePayVaultKey(userId),
        value: resolvedToken,
      );
      // Store ONLY non-sensitive masked status in Firestore (NEVER plaintext `apiToken`!)
      await _sePayConfigRef(userId).set(
        {
          'sourceId': 'sepay_api',
          'ownerId': userId,
          'hasTokenConfigured': true,
          'maskedToken': _maskSecretToken(resolvedToken),
          'apiToken': FieldValue.delete(),
          'defaultWalletId': walletId,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        },
        SetOptions(merge: true),
      );
    } else {
      resolvedToken =
          (await NativeSecureVaultBridge.instance.readSecret(_sePayVaultKey(userId)))?.trim() ?? '';
      if (resolvedToken.isEmpty) {
        final snap = await _sePayConfigRef(userId).get();
        final legacyPlain = (snap.data()?['apiToken'] as String?)?.trim() ?? '';
        if (legacyPlain.isNotEmpty) {
          resolvedToken = legacyPlain;
          await NativeSecureVaultBridge.instance.writeSecret(
            key: _sePayVaultKey(userId),
            value: legacyPlain,
          );
          await _sePayConfigRef(userId).set(
            {
              'hasTokenConfigured': true,
              'maskedToken': _maskSecretToken(legacyPlain),
              'apiToken': FieldValue.delete(),
            },
            SetOptions(merge: true),
          );
        }
      }
    }

    final remoteItems = await _sePayApi.fetchRecentTransactions(
      apiToken: resolvedToken,
      limit: limit,
    );

    var appliedCount = 0;
    for (final item in remoteItems) {
      final outcome = await ingestVerifiedBankFeedEvent(
        userId: userId,
        walletId: walletId,
        externalTransactionId: item.externalId,
        direction: item.direction,
        amountMinor: item.amountMinor,
        content: '${item.bankBrandName}: ${item.content}',
        occurredAt: item.occurredAt,
        referenceCode: item.referenceCode,
      );
      if (outcome.kind == IngestionOutcomeKind.upgradedToVerified) {
        appliedCount += 1;
      }
    }
    return appliedCount;
  }

  DocumentReference<Map<String, dynamic>> _consentRef(String userId) =>
      _firestore.collection('users').doc(userId).collection('consents').doc('android_notification');

  Stream<SourceConsentEntity> watchConsent(String userId) {
    return _consentRef(userId).snapshots().map((snap) {
      final d = snap.data() ?? const <String, dynamic>{};
      final pkgs = (d['allowedPackages'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList();
      final ts = d['updatedAt'];
      return SourceConsentEntity(
        sourceId: 'android_notification',
        ownerId: userId,
        enabled: (d['enabled'] as bool?) ?? false,
        autoConfirmSignals: (d['autoConfirmSignals'] as bool?) ?? false,
        allowedPackages: pkgs,
        updatedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      );
    });
  }

  Future<void> updateConsent({
    required String userId,
    required bool enabled,
    required List<String> allowedPackages,
    bool? autoConfirmSignals,
  }) async {
    final now = DateTime.now();
    final batch = _firestore.batch();
    batch.set(
      _consentRef(userId),
      {
        'sourceId': 'android_notification',
        'ownerId': userId,
        'enabled': enabled,
        if (autoConfirmSignals != null) 'autoConfirmSignals': autoConfirmSignals,
        'allowedPackages': allowedPackages,
        'updatedAt': Timestamp.fromDate(now),
      },
      SetOptions(merge: true),
    );

    // Section 17 & T19: When consent is revoked, immediately stop listener & reject unconfirmed provisional items
    if (!enabled) {
      final provSnap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('transactions')
          .where('verification', isEqualTo: 'provisional')
          .get();
      for (final doc in provSnap.docs) {
        if (doc.data()['sourceKind'] == 'androidNotification') {
          batch.update(doc.reference, {
            'verification': 'rejected',
            'updatedAt': Timestamp.fromDate(now),
          });
        }
      }
    }

    await batch.commit();
    await _bridge.syncConsentConfig(enabled: enabled, allowedPackages: allowedPackages);
  }

  Future<IngestionOutcome> ingestAndroidNotification({
    required String userId,
    required String defaultWalletId,
    required String packageName,
    required String title,
    required String body,
    DateTime? postedAt,
    String? notificationId,
  }) async {
    // Step 1: Hard OTP / secret filter BEFORE touching any database or log!
    if (OtpRedactor.containsOtpOrSecret('$title $body')) {
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.blockedOtpOrSecret,
        message: 'Đã chặn và hủy thông báo chứa mã OTP / thông tin bảo mật.',
      );
    }

    // Step 2: Check explicit user consent & package allowlist
    final consentSnap = await _consentRef(userId).get();
    final consentData = consentSnap.data() ?? const <String, dynamic>{};
    final enabled = (consentData['enabled'] as bool?) ?? false;
    final autoConfirm = (consentData['autoConfirmSignals'] as bool?) ?? false;
    final allowedPackages = (consentData['allowedPackages'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => e.toString())
        .toSet();

    if (!enabled || !allowedPackages.contains(packageName)) {
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.blockedConsentDisabled,
        message: 'Nguồn thông báo chưa được cấp quyền hoặc ngân hàng không nằm trong allowlist.',
      );
    }

    // Step 3: Parse bank notification
    final parsed = BankNotificationParser.parseAndroidNotification(
      ownerId: userId,
      packageName: packageName,
      title: title,
      body: body,
      postedAt: postedAt,
      notificationId: notificationId,
    );

    if (parsed.dropReason == BankSignalDropReason.otpOrSecret) {
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.blockedOtpOrSecret,
        message: 'Đã chặn thông báo chứa mã xác thực.',
      );
    }
    final signal = parsed.signal;
    if (signal == null) {
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.ignoredPackageOrFormat,
        message: 'Thông báo không phải biến động giao dịch tài chính.',
      );
    }

    final eventRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('source_events')
        .doc(signal.sourceEventKey);

    final softFp = BankNotificationParser.computeSoftWindowFingerprint(
      ownerId: userId,
      direction: signal.direction,
      amountMinor: signal.amountMinor,
      occurredAt: signal.occurredAt,
    );
    final candidateWindowFps = BankNotificationParser.computeOverlappingSoftWindowFingerprints(
      ownerId: userId,
      direction: signal.direction,
      amountMinor: signal.amountMinor,
      occurredAt: signal.occurredAt,
    );

    // Check if already confirmed/verified by an official feed within a true ±15m sliding window
    final existingTxQuery = await _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('softWindowFingerprint', whereIn: candidateWindowFps)
        .get();
    final matchingExistingDocs = existingTxQuery.docs.where((d) {
      final ts = d.data()['occurredAt'];
      if (ts is! Timestamp) return true;
      return ts.toDate().difference(signal.occurredAt).abs() <= const Duration(minutes: 15);
    }).toList();

    var isDuplicate = false;
    final txId = 'prov_${signal.sourceEventKey.substring(0, 20)}';

    await _firestore.runTransaction((tx) async {
      final existingEvent = await tx.get(eventRef);
      if (existingEvent.exists) {
        isDuplicate = true;
        return;
      }

      final now = DateTime.now();
      if (matchingExistingDocs.isNotEmpty) {
        isDuplicate = true;
        tx.set(eventRef, {
          'eventKey': signal.sourceEventKey,
          'source': 'android_notification',
          'status': 'duplicate_linked',
          'linkedTransactionId': matchingExistingDocs.first.id,
          'receivedAt': Timestamp.fromDate(now),
        });
        return;
      }

      final monthKey =
          '${signal.occurredAt.year.toString().padLeft(4, '0')}-${signal.occurredAt.month.toString().padLeft(2, '0')}';

      int? newWalletBal;
      String? resolvedWalletName;
      if (autoConfirm) {
        final walletRef =
            _firestore.collection('users').doc(userId).collection('wallets').doc(defaultWalletId);
        final wSnap = await tx.get(walletRef);
        if (wSnap.exists) {
          final curBal = (wSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
          final delta = signal.direction == 'credit' ? signal.amountMinor : -signal.amountMinor;
          newWalletBal = curBal + delta;
          resolvedWalletName = (wSnap.data()?['name'] as String?) ?? 'Ngân hàng';
          tx.update(walletRef, {
            'balanceMinor': newWalletBal,
            'updatedAt': Timestamp.fromDate(now),
          });
        }
      }

      tx.set(eventRef, {
        'eventKey': signal.sourceEventKey,
        'source': 'android_notification',
        'status': autoConfirm ? 'auto_confirmed' : 'provisional_created',
        'linkedTransactionId': txId,
        'receivedAt': Timestamp.fromDate(now),
      });

      tx.set(
        _firestore.collection('users').doc(userId).collection('transactions').doc(txId),
        {
          'id': txId,
          'ownerId': userId,
          'walletId': defaultWalletId,
          if (resolvedWalletName != null) 'walletName': resolvedWalletName,
          if (newWalletBal != null) 'balanceAfterMinor': newWalletBal,
          'categoryName': signal.categorySuggestion,
          'kind': signal.direction == 'credit' ? 'income' : 'expense',
          'direction': signal.direction,
          'amountMinor': signal.amountMinor,
          'currencyCode': 'VND',
          'merchant': '${signal.bankCode}: ${signal.merchant}',
          'occurredAt': Timestamp.fromDate(signal.occurredAt),
          'monthKey': monthKey,
          'sourceKind': 'androidNotification',
          'verification': autoConfirm ? 'userConfirmed' : 'provisional',
          'crossSourceFingerprint': signal.crossSourceFingerprint,
          'softWindowFingerprint': softFp,
          'isVehicleMaintenanceHint': signal.isVehicleMaintenanceHint,
          'schemaVersion': 1,
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        },
      );
    });

    if (isDuplicate) {
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.duplicateIgnored,
        message: 'Giao dịch trùng lặp đã được khử tự động.',
      );
    }

    return IngestionOutcome(
      kind: IngestionOutcomeKind.createdProvisional,
      transactionId: txId,
      message: 'Đã tạo gợi ý giao dịch PROVISIONAL chờ xác nhận.',
    );
  }

  Future<IngestionOutcome> ingestVerifiedBankFeedEvent({
    required String userId,
    required String walletId,
    required String externalTransactionId,
    required String direction,
    required int amountMinor,
    required String content,
    required DateTime occurredAt,
    String? referenceCode,
  }) async {
    final eventKey = BankNotificationParser.computeSourceEventKey(
      'bank_api',
      externalTransactionId,
    );
    final eventRef =
        _firestore.collection('users').doc(userId).collection('source_events').doc(eventKey);

    final softFp = BankNotificationParser.computeSoftWindowFingerprint(
      ownerId: userId,
      direction: direction,
      amountMinor: amountMinor,
      occurredAt: occurredAt,
    );
    final candidateWindowFps = BankNotificationParser.computeOverlappingSoftWindowFingerprints(
      ownerId: userId,
      direction: direction,
      amountMinor: amountMinor,
      occurredAt: occurredAt,
    );

    // Look for an unconfirmed PROVISIONAL transaction within ±15m sliding window to upgrade (Scenario T07)!
    final provMatches = await _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('softWindowFingerprint', whereIn: candidateWindowFps)
        .get();

    final matchingProvDoc = provMatches.docs.where((d) {
      if (d.data()['verification'] != 'provisional') return false;
      final ts = d.data()['occurredAt'];
      if (ts is! Timestamp) return true;
      return ts.toDate().difference(occurredAt).abs() <= const Duration(minutes: 15);
    }).firstOrNull;

    var outcomeKind = IngestionOutcomeKind.upgradedToVerified;
    var targetTxId = matchingProvDoc?.id ?? 'ver_${eventKey.substring(0, 20)}';

    await _firestore.runTransaction((tx) async {
      final evSnap = await tx.get(eventRef);
      if (evSnap.exists) {
        outcomeKind = IngestionOutcomeKind.duplicateIgnored;
        return;
      }

      final walletRef =
          _firestore.collection('users').doc(userId).collection('wallets').doc(walletId);
      final walletSnap = await tx.get(walletRef);
      final currentBal = (walletSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
      final delta = direction == 'credit' ? amountMinor : -amountMinor;
      final now = DateTime.now();

      tx.set(eventRef, {
        'eventKey': eventKey,
        'source': 'bank_api',
        'status': 'verified_processed',
        'linkedTransactionId': targetTxId,
        'receivedAt': Timestamp.fromDate(now),
      });

      final newWalletBalance = currentBal + delta;
      final resolvedWalletName = (walletSnap.data()?['name'] as String?) ?? 'Ngân hàng';

      if (walletSnap.exists) {
        tx.update(walletRef, {
          'balanceMinor': newWalletBalance,
          'updatedAt': Timestamp.fromDate(now),
        });
      }

      if (matchingProvDoc != null) {
        // Upgrade provisional -> verified without creating a second transaction!
        tx.update(matchingProvDoc.reference, {
          'verification': 'verified',
          'sourceKind': 'bankApi',
          'walletId': walletId,
          'walletName': resolvedWalletName,
          'balanceAfterMinor': newWalletBalance,
          'updatedAt': Timestamp.fromDate(now),
        });
      } else {
        targetTxId = 'ver_${eventKey.substring(0, 20)}';
        final inferred = BankNotificationParser.inferCategory(content, direction);
        final monthKey =
            '${occurredAt.year.toString().padLeft(4, '0')}-${occurredAt.month.toString().padLeft(2, '0')}';
        tx.set(
          _firestore.collection('users').doc(userId).collection('transactions').doc(targetTxId),
          {
            'id': targetTxId,
            'ownerId': userId,
            'walletId': walletId,
            'walletName': resolvedWalletName,
            'balanceAfterMinor': newWalletBalance,
            'categoryName': inferred.category,
            'kind': direction == 'credit' ? 'income' : 'expense',
            'direction': direction,
            'amountMinor': amountMinor,
            'currencyCode': 'VND',
            'merchant': content,
            'occurredAt': Timestamp.fromDate(occurredAt),
            'monthKey': monthKey,
            'sourceKind': 'bankApi',
            'verification': 'verified',
            'crossSourceFingerprint': BankNotificationParser.computeCrossSourceFingerprint(
              ownerId: userId,
              direction: direction,
              amountMinor: amountMinor,
              occurredAt: occurredAt,
              referenceCode: referenceCode,
            ),
            'softWindowFingerprint': softFp,
            'isVehicleMaintenanceHint': inferred.isVehicleMaintenance,
            'schemaVersion': 1,
            'createdAt': Timestamp.fromDate(now),
            'updatedAt': Timestamp.fromDate(now),
          },
        );
      }
    });

    return IngestionOutcome(
      kind: outcomeKind,
      transactionId: targetTxId,
      message: outcomeKind == IngestionOutcomeKind.duplicateIgnored
          ? 'Sự kiện ngân hàng trùng lặp đã bỏ qua (idempotent).'
          : 'Đã xác thực giao dịch VERIFIED và cập nhật số dư.',
    );
  }

  Future<String> exportPersonalDataJson(String userId) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final wallets = await _firestore.collection('users').doc(userId).collection('wallets').get();
    final txs = await _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .limit(200)
        .get();
    final privEvents =
        await _firestore.collection('users').doc(userId).collection('private_events').get();

    Map<String, dynamic> sanitizeMap(Map<String, dynamic>? m) {
      if (m == null) return {};
      return m.map((k, v) {
        if (v is Timestamp) return MapEntry(k, v.toDate().toIso8601String());
        return MapEntry(k, v);
      });
    }

    final payload = {
      'exportedAt': DateTime.now().toIso8601String(),
      'compliance': 'Vietnam PDPL 91/2025/QH15',
      'profile': sanitizeMap(userDoc.data()),
      'wallets': wallets.docs.map((d) => sanitizeMap(d.data())).toList(),
      'transactions': txs.docs.map((d) => sanitizeMap(d.data())).toList(),
      'privateEvents': privEvents.docs.map((d) => sanitizeMap(d.data())).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<int> importCsvStatement({
    required String userId,
    required String walletId,
    required String csvContent,
  }) async {
    final lines = csvContent
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return 0;

    var importedCount = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Skip CSV header line if present
      if (i == 0 && RegExp(r'(date|ngay|amount|so_tien|description)', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      if (OtpRedactor.containsOtpOrSecret(line)) {
        continue;
      }

      // Expected columns: YYYY-MM-DD, direction(debit|credit|-|+), amount, description
      final cols = line.split(',').map((c) => c.trim()).toList();
      if (cols.length < 3) continue;

      final parsedDate = DateTime.tryParse(cols[0]) ?? DateTime.now();
      final rawDir = cols[1].toLowerCase();
      final direction =
          (rawDir == 'credit' || rawDir == 'in' || rawDir == '+') ? 'credit' : 'debit';
      final amountMinor = VndAmount.tryParseInput(cols[2]);
      if (amountMinor == null || amountMinor <= 0) continue;
      final desc = cols.length >= 4 && cols[3].isNotEmpty ? cols.sublist(3).join(', ') : 'Sao kê CSV';

      final rowEventKey = BankNotificationParser.computeSourceEventKey(
        'csv',
        '$userId:$walletId:${cols[0]}:$direction:$amountMinor:$desc',
      );
      final eventRef =
          _firestore.collection('users').doc(userId).collection('source_events').doc(rowEventKey);
      final txId = 'csv_${rowEventKey.substring(0, 20)}';
      final txRef =
          _firestore.collection('users').doc(userId).collection('transactions').doc(txId);
      final walletRef =
          _firestore.collection('users').doc(userId).collection('wallets').doc(walletId);

      await _firestore.runTransaction((tx) async {
        final existing = await tx.get(eventRef);
        if (existing.exists) return;

        final wSnap = await tx.get(walletRef);
        final currentBal = (wSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
        final delta = direction == 'credit' ? amountMinor : -amountMinor;
        final now = DateTime.now();
        final inferred = BankNotificationParser.inferCategory(desc, direction);
        final monthKey =
            '${parsedDate.year.toString().padLeft(4, '0')}-${parsedDate.month.toString().padLeft(2, '0')}';

        tx.set(eventRef, {
          'eventKey': rowEventKey,
          'source': 'csv',
          'status': 'confirmed_imported',
          'linkedTransactionId': txId,
          'receivedAt': Timestamp.fromDate(now),
        });

        if (wSnap.exists) {
          tx.update(walletRef, {
            'balanceMinor': currentBal + delta,
            'updatedAt': Timestamp.fromDate(now),
          });
        }

        tx.set(txRef, {
          'id': txId,
          'ownerId': userId,
          'walletId': walletId,
          'categoryName': inferred.category,
          'kind': direction == 'credit' ? 'income' : 'expense',
          'direction': direction,
          'amountMinor': amountMinor,
          'currencyCode': 'VND',
          'merchant': desc,
          'occurredAt': Timestamp.fromDate(parsedDate),
          'monthKey': monthKey,
          'sourceKind': 'csv',
          'verification': 'userConfirmed',
          'crossSourceFingerprint': BankNotificationParser.computeCrossSourceFingerprint(
            ownerId: userId,
            direction: direction,
            amountMinor: amountMinor,
            occurredAt: parsedDate,
          ),
          'isVehicleMaintenanceHint': inferred.isVehicleMaintenance,
          'schemaVersion': 1,
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        });
        importedCount += 1;
      });
    }
    return importedCount;
  }

  Future<void> deleteAccountAndPersonalData(String userId) async {
    await _bridge.syncConsentConfig(enabled: false, allowedPackages: const []);
    await NativeSecureVaultBridge.instance.clearAllSecrets();
    await NativeAlarmSchedulerBridge.instance.clearAllAlarms();

    final userDocRef = _firestore.collection('users').doc(userId);
    // Mark account deletion active so Cloud Firestore Security Rules allow purging append-only ledgers
    await userDocRef.set(
      {
        'id': userId,
        'deletionInProgress': true,
        'deletionStartedAt': Timestamp.fromDate(DateTime.now()),
      },
      SetOptions(merge: true),
    );

    // Revoke any published Busy/Free slots & remove user from shared families without deleting family ledgers
    final famSnap = await _firestore
        .collection('families')
        .where('memberIds', arrayContains: userId)
        .get();
    for (final famDoc in famSnap.docs) {
      try {
        final availSnap = await famDoc.reference
            .collection('availability')
            .where('ownerId', isEqualTo: userId)
            .get();
        for (final slot in availSnap.docs) {
          await slot.reference.delete();
        }
      } catch (_) {}

      final d = famDoc.data();
      final members = (d['memberIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .where((id) => id != userId)
          .toList();
      final roles = Map<String, dynamic>.from((d['memberRoles'] as Map?) ?? {})..remove(userId);
      final names = Map<String, dynamic>.from((d['memberNames'] as Map?) ?? {})..remove(userId);
      await famDoc.reference.update({
        'memberIds': members,
        'memberRoles': roles,
        'memberNames': names,
      });
    }

    // Purge nested subcollections inside personal_funds & vehicles first
    final pFundsSnap = await userDocRef.collection('personal_funds').get();
    for (final fundDoc in pFundsSnap.docs) {
      for (final nested in const ['contributions', 'expenses']) {
        final nSnap = await fundDoc.reference.collection(nested).get();
        for (final nDoc in nSnap.docs) {
          await nDoc.reference.delete();
        }
      }
    }
    final vehiclesSnap = await userDocRef.collection('vehicles').get();
    for (final vDoc in vehiclesSnap.docs) {
      final mSnap = await vDoc.reference.collection('maintenances').get();
      for (final mDoc in mSnap.docs) {
        await mDoc.reference.delete();
      }
    }

    // Purge ALL 28 personal subcollections (including transactions, audits, health, kitchen, notes & vault metadata)
    const allPersonalSubcollections = [
      'wallets',
      'ledger_audits',
      'net_worth_snapshots',
      'categories',
      'transactions',
      'budgets',
      'personal_funds',
      'calendars',
      'private_events',
      'personal_tasks',
      'vehicles',
      'bills',
      'consents',
      'source_events',
      'documents',
      'subscriptions_warranties',
      'habits',
      'wellness_daily',
      'gift_ledger',
      'packing_items',
      'medications',
      'health_logs',
      'medical_profiles',
      'grocery_items',
      'meal_plans',
      'utility_readings',
      'home_contracts',
      'life_notes',
    ];
    for (final sub in allPersonalSubcollections) {
      final subSnap = await userDocRef.collection(sub).get();
      for (final d in subSnap.docs) {
        await d.reference.delete();
      }
    }
    await userDocRef.delete();

    final current = _firebaseAuth.currentUser;
    if (current != null && current.uid == userId) {
      try {
        await current.delete();
      } catch (_) {
        await _firebaseAuth.signOut();
      }
    } else {
      await _firebaseAuth.signOut();
    }
  }
}

class NotificationsRepositoryImpl implements NotificationsRepository {
  final NotificationsRemoteDataSource _remoteDataSource;
  const NotificationsRepositoryImpl(this._remoteDataSource);

  @override
  Stream<Result<SourceConsentEntity>> watchAndroidNotificationConsent(String userId) {
    return _remoteDataSource
        .watchConsent(userId)
        .map<Result<SourceConsentEntity>>((c) => Success(c))
        .transform(
          StreamTransformer.fromHandlers(
            handleError: (Object e, StackTrace _, EventSink<Result<SourceConsentEntity>> sink) {
              sink.add(Err(ErrorMapper.map(e)));
            },
          ),
        );
  }

  @override
  Future<Result<void>> updateAndroidNotificationConsent({
    required String userId,
    required bool enabled,
    required List<String> allowedPackages,
    bool? autoConfirmSignals,
  }) async {
    try {
      await _remoteDataSource.updateConsent(
        userId: userId,
        enabled: enabled,
        allowedPackages: allowedPackages,
        autoConfirmSignals: autoConfirmSignals,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<IngestionOutcome>> ingestAndroidNotification({
    required String userId,
    required String defaultWalletId,
    required String packageName,
    required String title,
    required String body,
    DateTime? postedAt,
    String? notificationId,
  }) async {
    try {
      final res = await _remoteDataSource.ingestAndroidNotification(
        userId: userId,
        defaultWalletId: defaultWalletId,
        packageName: packageName,
        title: title,
        body: body,
        postedAt: postedAt,
        notificationId: notificationId,
      );
      return Success(res);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<IngestionOutcome>> ingestVerifiedBankFeedEvent({
    required String userId,
    required String walletId,
    required String externalTransactionId,
    required String direction,
    required int amountMinor,
    required String content,
    required DateTime occurredAt,
    String? referenceCode,
  }) async {
    try {
      final res = await _remoteDataSource.ingestVerifiedBankFeedEvent(
        userId: userId,
        walletId: walletId,
        externalTransactionId: externalTransactionId,
        direction: direction,
        amountMinor: amountMinor,
        content: content,
        occurredAt: occurredAt,
        referenceCode: referenceCode,
      );
      return Success(res);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<int>> importCsvStatement({
    required String userId,
    required String walletId,
    required String csvContent,
  }) async {
    try {
      final count = await _remoteDataSource.importCsvStatement(
        userId: userId,
        walletId: walletId,
        csvContent: csvContent,
      );
      return Success(count);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<String>> exportPersonalDataJson(String userId) async {
    try {
      final jsonStr = await _remoteDataSource.exportPersonalDataJson(userId);
      return Success(jsonStr);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> deleteAccountAndPersonalData(String userId) async {
    try {
      await _remoteDataSource.deleteAccountAndPersonalData(userId);
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<bool> isNativeNotificationAccessGranted() =>
      _remoteDataSource.isNativePermissionGranted();

  @override
  Future<void> openNativeNotificationAccessSettings() =>
      _remoteDataSource.openNativePermissionSettings();

  @override
  Stream<Map<String, dynamic>> watchLiveAndroidBankSignals() =>
      _remoteDataSource.watchLiveNativeSignals();

  @override
  Future<List<Map<String, dynamic>>> drainQueuedAndroidBankSignals() =>
      _remoteDataSource.drainQueuedNativeSignals();

  @override
  Future<Result<String?>> getSavedSePayMaskedToken(String userId) async {
    try {
      final masked = await _remoteDataSource.getSavedSePayMaskedToken(userId);
      return Success(masked);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<int>> syncSePayTransactions({
    required String userId,
    required String walletId,
    String? apiTokenOverride,
    int limit = 40,
  }) async {
    try {
      final count = await _remoteDataSource.syncSePayTransactions(
        userId: userId,
        walletId: walletId,
        apiTokenOverride: apiTokenOverride,
        limit: limit,
      );
      return Success(count);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
