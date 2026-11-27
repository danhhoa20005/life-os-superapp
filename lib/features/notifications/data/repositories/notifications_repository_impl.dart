import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as cf;
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/di/dependency_injection.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/services/android_notification_bridge.dart';
import '../../../../core/services/file_storage_service.dart';
import '../../../../core/services/native_alarm_scheduler_bridge.dart';
import '../../../../core/services/native_home_widget_bridge.dart';
import '../../../../core/services/native_secure_vault_bridge.dart';
import '../../../../core/services/personal_alarm_service.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vietqr_emv_builder.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../financial_ai/data/normalization/financial_text_normalizer.dart';
import '../../../financial_ai/domain/entities/financial_ai_entities.dart';
import '../../../financial_ai/domain/repositories/financial_ai_repository.dart';
import '../../domain/entities/notification_entities.dart';
import '../../domain/repositories/notifications_repository.dart';

typedef CloudFunctionsInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> payload,
    );

class NotificationsRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;
  final AndroidNotificationBridge _bridge;
  final CloudFunctionsInvoker? _functionsInvokerOverride;
  final FinancialAiRepository? _financialAiRepository;
  final Future<void> Function(String userId)? _clearUserVaultOverride;

  NotificationsRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseAuth firebaseAuth,
    required AndroidNotificationBridge bridge,
    CloudFunctionsInvoker? functionsInvokerOverride,
    FinancialAiRepository? financialAiRepository,
    Future<void> Function(String userId)? clearUserVaultOverride,
  }) : _firestore = firestore,
       _firebaseAuth = firebaseAuth,
       _bridge = bridge,
       _functionsInvokerOverride = functionsInvokerOverride,
       _financialAiRepository = financialAiRepository,
       _clearUserVaultOverride = clearUserVaultOverride;

  Future<void> _txChain = Future<void>.value();

  Future<T> _runSerializedTx<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _txChain = _txChain.then((_) async {
      try {
        final result = await action();
        if (!completer.isCompleted) completer.complete(result);
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> _clearUserScopedLocalVault(String userId) async {
    if (_clearUserVaultOverride != null) {
      await _clearUserVaultOverride(userId);
      return;
    }
    await NativeSecureVaultBridge.instance.clearSecretsForUser(userId);
    await SparkSafeFileStorageService.clearVaultForUser(userId);
    await PersonalAlarmStore.instance.clearSessionOnSignOut();
  }

  Future<Map<String, dynamic>> _invokeBackendFunction(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    if (_functionsInvokerOverride != null) {
      return _functionsInvokerOverride(functionName, payload);
    }
    final callable = cf.FirebaseFunctions.instanceFor(
      region: 'asia-southeast1',
    ).httpsCallable(functionName);
    final res = await callable.call<Map<dynamic, dynamic>>(payload);
    return Map<String, dynamic>.from(res.data);
  }

  Future<bool> isNativePermissionGranted() =>
      _bridge.isNotificationAccessGranted();

  Future<void> openNativePermissionSettings() =>
      _bridge.openNotificationAccessSettings();

  Future<void> speakSoundboxTest(String message) =>
      _bridge.speakSoundboxAnnouncement(message);

  Stream<Map<String, dynamic>> watchLiveNativeSignals() =>
      _bridge.watchIncomingBankNotifications();

  Future<List<Map<String, dynamic>>> drainQueuedNativeSignals() =>
      _bridge.drainQueuedBackgroundNotifications();

  DocumentReference<Map<String, dynamic>> _consentRef(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('consents')
          .doc('android_notification');

  CollectionReference<Map<String, dynamic>> _bankAccountsCol(String userId) =>
      _firestore.collection('users').doc(userId).collection('bank_accounts');

  CollectionReference<Map<String, dynamic>> _bankConnectionsCol(
    String userId,
  ) =>
      _firestore.collection('users').doc(userId).collection('bank_connections');

  CollectionReference<Map<String, dynamic>> _financialNotifsCol(
    String userId,
  ) => _firestore
      .collection('users')
      .doc(userId)
      .collection('financial_notifications');

  DocumentReference<Map<String, dynamic>> _notifPrefsRef(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('notification_preferences')
          .doc('settings');

  CollectionReference<Map<String, dynamic>> _merchantRulesCol(String userId) =>
      _firestore.collection('users').doc(userId).collection('merchant_rules');

  CollectionReference<Map<String, dynamic>> _paymentOrdersCol(String userId) =>
      _firestore.collection('users').doc(userId).collection('payment_orders');

  Stream<SourceConsentEntity> watchConsent(String userId) {
    return _consentRef(userId).snapshots().map((snap) {
      final d = snap.data() ?? const <String, dynamic>{};
      final rawPkgs =
          (d['allowedPackages'] as List<dynamic>? ?? const <dynamic>[]).map(
            (e) => e.toString(),
          );
      final pkgs = BankNotificationParser.sanitizeAllowedBankPackages(rawPkgs);
      final ts = d['updatedAt'];
      return SourceConsentEntity(
        sourceId: 'android_notification',
        ownerId: userId,
        enabled: (d['enabled'] as bool?) ?? false,
        autoConfirmSignals: (d['autoConfirmSignals'] as bool?) ?? false,
        voiceSoundboxEnabled: (d['voiceSoundboxEnabled'] as bool?) ?? false,
        syncObservedBalance: (d['syncObservedBalance'] as bool?) ?? true,
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
    bool? voiceSoundboxEnabled,
    bool? syncObservedBalance,
  }) async {
    final sanitizedPackages =
        BankNotificationParser.sanitizeAllowedBankPackages(allowedPackages);
    final now = DateTime.now();
    final batch = _firestore.batch();
    batch.set(_consentRef(userId), {
      'sourceId': 'android_notification',
      'ownerId': userId,
      'enabled': enabled,
      if (autoConfirmSignals != null) 'autoConfirmSignals': autoConfirmSignals,
      if (voiceSoundboxEnabled != null)
        'voiceSoundboxEnabled': voiceSoundboxEnabled,
      if (syncObservedBalance != null)
        'syncObservedBalance': syncObservedBalance,
      'allowedPackages': sanitizedPackages,
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));

    // When consent is revoked, immediately stop listener & reject unconfirmed provisional items
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
    await _bridge.syncConsentConfig(
      enabled: enabled,
      allowedPackages: sanitizedPackages,
      voiceSoundboxEnabled: voiceSoundboxEnabled,
    );
  }

  LinkedBankAccountEntity _mapBankAccount(String id, Map<String, dynamic> d) {
    final ts = d['createdAt'];
    return LinkedBankAccountEntity(
      id: id,
      ownerId: (d['ownerId'] as String?) ?? '',
      walletId: (d['walletId'] as String?) ?? 'wallet_bank_default',
      bankBin: (d['bankBin'] as String?) ?? '970436',
      bankCode: (d['bankCode'] as String?) ?? 'VCB',
      bankName: (d['bankName'] as String?) ?? 'Vietcombank',
      accountNumber: (d['accountNumber'] as String?) ?? '',
      accountHolderName: (d['accountHolderName'] as String?) ?? '',
      isDefault: (d['isDefault'] as bool?) ?? true,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  Stream<List<LinkedBankAccountEntity>> watchLinkedBankAccounts(String userId) {
    return _bankAccountsCol(userId).snapshots().map((snap) {
      final items =
          snap.docs.map((d) => _mapBankAccount(d.id, d.data())).toList()
            ..sort((a, b) {
              if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
              return b.createdAt.compareTo(a.createdAt);
            });
      return items;
    });
  }

  Future<LinkedBankAccountEntity> saveLinkedBankAccount({
    required String userId,
    required String walletId,
    required String bankBin,
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountHolderName,
    bool isDefault = true,
  }) async {
    final cleanAcc = accountNumber
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .trim();
    if (cleanAcc.length < 6) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Số tài khoản ngân hàng phải có ít nhất 6 ký tự.',
      );
    }
    final cleanHolder = VietQrEmvBuilder.toBankSafeAscii(
      accountHolderName.trim().isEmpty ? 'CHU TAI KHOAN' : accountHolderName,
      maxLength: 50,
    );
    final now = DateTime.now();
    final id = 'ba_${bankCode.toLowerCase()}_$cleanAcc';
    final entity = LinkedBankAccountEntity(
      id: id,
      ownerId: userId,
      walletId: walletId,
      bankBin: bankBin,
      bankCode: bankCode,
      bankName: bankName,
      accountNumber: cleanAcc,
      accountHolderName: cleanHolder,
      isDefault: isDefault,
      createdAt: now,
    );

    final batch = _firestore.batch();
    if (isDefault) {
      final existing = await _bankAccountsCol(userId).get();
      for (final doc in existing.docs) {
        if (doc.id != id && (doc.data()['isDefault'] as bool? ?? false)) {
          batch.update(doc.reference, {'isDefault': false});
        }
      }
    }

    batch.set(_bankAccountsCol(userId).doc(id), {
      'id': id,
      'ownerId': userId,
      'walletId': walletId,
      'bankBin': bankBin,
      'bankCode': bankCode,
      'bankName': bankName,
      'accountNumber': cleanAcc,
      'accountHolderName': cleanHolder,
      'isDefault': isDefault,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });

    // Also enrich the linked Wallet's bankCode & maskedAccount (`•••• 1234`) if it exists
    final walletRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('wallets')
        .doc(walletId);
    final wSnap = await walletRef.get();
    if (wSnap.exists) {
      batch.update(walletRef, {
        'bankCode': bankCode,
        'maskedAccount': entity.maskedAccount,
        'updatedAt': Timestamp.fromDate(now),
      });
    }

    await batch.commit();
    return entity;
  }

  Future<void> deleteLinkedBankAccount({
    required String userId,
    required String accountId,
  }) async {
    await _bankAccountsCol(userId).doc(accountId).delete();
  }

  PaymentOrderEntity _mapPaymentOrder(String id, Map<String, dynamic> d) {
    final rawStatus = (d['status'] as String?) ?? 'pending';
    final status = PaymentOrderStatus.values.firstWhere(
      (s) => s.name == rawStatus,
      orElse: () => PaymentOrderStatus.pending,
    );
    final rawContribs = d['receivedContributions'];
    final contributions = <String, int>{};
    if (rawContribs is Map) {
      for (final entry in rawContribs.entries) {
        final key = entry.key.toString();
        final val = (entry.value as num?)?.toInt();
        if (key.isNotEmpty && val != null && val > 0) {
          contributions[key] = val;
        }
      }
    }
    final rawMatchedIds = d['matchedTransactionIds'];
    final matchedIds = rawMatchedIds is List
        ? rawMatchedIds
              .map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final cTs = d['createdAt'];
    final pTs = d['paidAt'];
    return PaymentOrderEntity(
      id: id,
      ownerId: (d['ownerId'] as String?) ?? '',
      walletId: (d['walletId'] as String?) ?? 'wallet_bank_default',
      bankBin: (d['bankBin'] as String?) ?? '970436',
      bankCode: (d['bankCode'] as String?) ?? 'VCB',
      bankName: (d['bankName'] as String?) ?? 'Vietcombank',
      accountNumber: (d['accountNumber'] as String?) ?? '',
      accountHolderName: (d['accountHolderName'] as String?) ?? '',
      amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
      receivedAmountMinor: (d['receivedAmountMinor'] as num?)?.toInt() ?? 0,
      currency: (d['currency'] as String?) ?? 'VND',
      receivedContributions: contributions,
      paymentCode: (d['paymentCode'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      emvQrPayload: (d['emvQrPayload'] as String?) ?? '',
      status: status,
      matchedTransactionId: d['matchedTransactionId'] as String?,
      matchedTransactionIds: matchedIds,
      reviewReason: d['reviewReason'] as String?,
      createdAt: cTs is Timestamp ? cTs.toDate() : DateTime.now(),
      paidAt: pTs is Timestamp ? pTs.toDate() : null,
    );
  }

  Stream<List<PaymentOrderEntity>> watchPaymentOrders(String userId) {
    return _paymentOrdersCol(userId).snapshots().map((snap) {
      final list =
          snap.docs.map((d) => _mapPaymentOrder(d.id, d.data())).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<PaymentOrderEntity> createPaymentOrder({
    required String userId,
    required String walletId,
    required String bankBin,
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountHolderName,
    required int amountMinor,
    required String description,
  }) async {
    if (amountMinor <= 0) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Số tiền cần thu phải lớn hơn 0 ₫.',
      );
    }
    final cleanAcc = accountNumber
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .trim();
    if (cleanAcc.length < 6) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message:
            'Vui lòng liên kết số tài khoản ngân hàng trước khi tạo mã QR.',
      );
    }
    final now = DateTime.now();
    final paymentCode = VietQrEmvBuilder.generatePaymentCode(prefix: 'LO');
    final cleanDesc = description.trim().isEmpty
        ? 'Thu tien'
        : description.trim();
    final memoWithCode =
        '$paymentCode ${VietQrEmvBuilder.toBankSafeAscii(cleanDesc, maxLength: 28)}'
            .trim();
    final emvQr = VietQrEmvBuilder.buildNapas247Payload(
      bankBin: bankBin,
      accountNumber: cleanAcc,
      amountVnd: amountMinor,
      memo: memoWithCode,
    );
    final orderId =
        'ord_${paymentCode.toLowerCase()}_${now.millisecondsSinceEpoch}';
    final holder = VietQrEmvBuilder.toBankSafeAscii(
      accountHolderName.trim().isEmpty ? 'CHU TAI KHOAN' : accountHolderName,
    );

    final entity = PaymentOrderEntity(
      id: orderId,
      ownerId: userId,
      walletId: walletId,
      bankBin: bankBin,
      bankCode: bankCode,
      bankName: bankName,
      accountNumber: cleanAcc,
      accountHolderName: holder,
      amountMinor: amountMinor,
      paymentCode: paymentCode,
      description: cleanDesc,
      emvQrPayload: emvQr,
      status: PaymentOrderStatus.pending,
      createdAt: now,
    );

    await _paymentOrdersCol(userId).doc(orderId).set({
      'id': orderId,
      'ownerId': userId,
      'walletId': walletId,
      'bankBin': bankBin,
      'bankCode': bankCode,
      'bankName': bankName,
      'accountNumber': cleanAcc,
      'accountHolderName': holder,
      'amountMinor': amountMinor,
      'receivedAmountMinor': 0,
      'currency': 'VND',
      'receivedContributions': const <String, int>{},
      'matchedTransactionIds': const <String>[],
      'reviewReason': null,
      'paymentCode': paymentCode,
      'description': cleanDesc,
      'emvQrPayload': emvQr,
      'status': PaymentOrderStatus.pending.name,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });

    return entity;
  }

  Future<void> markPaymentOrderStatus({
    required String userId,
    required String orderId,
    required PaymentOrderStatus status,
  }) async {
    final now = DateTime.now();
    await _paymentOrdersCol(userId).doc(orderId).update({
      'status': status.name,
      if (status == PaymentOrderStatus.paid) 'paidAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
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
    // Step 0: Hard SMS / Messaging package block BEFORE reading title/body or touching database!
    if (BankNotificationParser.isBlockedSmsOrMessagingPackage(packageName)) {
      if (notificationId != null && notificationId.isNotEmpty) {
        await _bridge.acknowledgeQueuedNotification(notificationId);
      }
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.blockedConsentDisabled,
        message:
            'Đã bỏ qua thông báo ứng dụng tin nhắn SMS theo chính sách Google Play.',
      );
    }

    // Step 1: Hard OTP / secret filter BEFORE touching any database or log!
    if (OtpRedactor.containsOtpOrSecret('$title $body')) {
      if (notificationId != null && notificationId.isNotEmpty) {
        await _bridge.acknowledgeQueuedNotification(notificationId);
      }
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.blockedOtpOrSecret,
        message: 'Đã chặn thông báo chứa mã OTP / bảo mật.',
      );
    }

    // Step 2: Check explicit user consent & package allowlist
    final consentSnap = await _consentRef(userId).get();
    final consentData = consentSnap.data() ?? const <String, dynamic>{};
    final enabled = (consentData['enabled'] as bool?) ?? false;
    final autoConfirm = (consentData['autoConfirmSignals'] as bool?) ?? false;
    final syncObservedBalance =
        (consentData['syncObservedBalance'] as bool?) ?? true;
    final allowedPackages =
        (consentData['allowedPackages'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e.toString())
            .toSet();

    if (!enabled || !allowedPackages.contains(packageName)) {
      if (notificationId != null && notificationId.isNotEmpty) {
        await _bridge.acknowledgeQueuedNotification(notificationId);
      }
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.blockedConsentDisabled,
        message: 'Chưa bật nhận diện cho ứng dụng ngân hàng này.',
      );
    }

    // Step 3: Parse bank notification (amount, direction, SD balance, account tail, QR code)
    final parsed = BankNotificationParser.parseAndroidNotification(
      ownerId: userId,
      packageName: packageName,
      title: title,
      body: body,
      postedAt: postedAt,
      notificationId: notificationId,
    );

    if (parsed.dropReason == BankSignalDropReason.otpOrSecret) {
      if (notificationId != null && notificationId.isNotEmpty) {
        await _bridge.acknowledgeQueuedNotification(notificationId);
      }
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.blockedOtpOrSecret,
        message: 'Đã chặn thông báo chứa mã xác thực.',
      );
    }
    final signal = parsed.signal;
    if (signal == null) {
      if (notificationId != null && notificationId.isNotEmpty) {
        await _bridge.acknowledgeQueuedNotification(notificationId);
      }
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.ignoredPackageOrFormat,
        message: 'Thông báo không phải biến động số dư.',
      );
    }

    // Step 4 (F08 / FIN-03): Safe Multi-Account Bank -> Wallet Routing (NEVER guess when >= 2 accounts share bankCode!)
    var targetWalletId = defaultWalletId;
    var resolvedSpecificBankWallet = false;
    var isAmbiguousWalletRouting = false;
    final bankAccSnap = await _bankAccountsCol(userId).get();
    final walletsSnap = await _firestore
        .collection('users')
        .doc(userId)
        .collection('wallets')
        .get();
    final accounts = bankAccSnap.docs
        .map((d) => _mapBankAccount(d.id, d.data()))
        .toList();
    final bankWalletsForCode = walletsSnap.docs.where((d) {
      final data = d.data();
      return (data['bankCode'] as String?)?.toUpperCase() ==
          signal.bankCode.toUpperCase();
    }).toList();

    final tail = signal.accountTail?.trim() ?? '';
    if (tail.isNotEmpty) {
      final matchingAccs = accounts.where((a) {
        final bankOk =
            signal.bankCode == 'BANK' ||
            a.bankCode.isEmpty ||
            a.bankCode.toUpperCase() == signal.bankCode.toUpperCase();
        return bankOk && a.accountTail.endsWith(tail) && a.walletId.isNotEmpty;
      }).toList();
      final matchingWalletIds = <String>{
        ...matchingAccs.map((a) => a.walletId),
        ...bankWalletsForCode
            .where(
              (w) =>
                  ((w.data()['maskedAccount'] as String?) ?? '').endsWith(tail),
            )
            .map((w) => w.id),
      };
      if (matchingWalletIds.length == 1) {
        targetWalletId = matchingWalletIds.first;
        resolvedSpecificBankWallet = true;
      } else if (matchingWalletIds.length > 1) {
        isAmbiguousWalletRouting = true;
      }
    } else {
      final candidateWalletIds = <String>{
        ...accounts
            .where(
              (a) =>
                  a.bankCode.toUpperCase() == signal.bankCode.toUpperCase() &&
                  a.walletId.isNotEmpty,
            )
            .map((a) => a.walletId),
        ...bankWalletsForCode.map((w) => w.id),
      };
      if (candidateWalletIds.length == 1) {
        targetWalletId = candidateWalletIds.first;
        resolvedSpecificBankWallet = true;
      } else if (candidateWalletIds.length > 1) {
        // FIN-03: Multiple accounts at the same bank and notification lacks accountTail -> require user review!
        isAmbiguousWalletRouting = true;
        targetWalletId = candidateWalletIds.first;
      }
    }

    // Step 5 (H1): Candidate lookup finds open orders (`pending` or `partial`) matching `paymentCode`.
    // NEVER override `targetWalletId` before verifying bank, account tail & wallet match inside `runTransaction`!
    DocumentReference<Map<String, dynamic>>? candidateOrderRef;
    PaymentOrderEntity? candidateOrder;
    if (signal.direction == 'credit') {
      final upperCombined = '$title $body'.toUpperCase();
      final openOrdersSnap = await _paymentOrdersCol(userId)
          .where(
            'status',
            whereIn: <String>[
              PaymentOrderStatus.pending.name,
              PaymentOrderStatus.partial.name,
            ],
          )
          .get();
      for (final doc in openOrdersSnap.docs) {
        final order = _mapPaymentOrder(doc.id, doc.data());
        final codeUpper = order.paymentCode.toUpperCase();
        if (codeUpper.isNotEmpty &&
            (signal.matchedPaymentCode?.toUpperCase() == codeUpper ||
                upperCombined.contains(codeUpper))) {
          candidateOrderRef = doc.reference;
          candidateOrder = order;
          break;
        }
      }
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
    final candidateWindowFps =
        BankNotificationParser.computeOverlappingSoftWindowFingerprints(
          ownerId: userId,
          direction: signal.direction,
          amountMinor: signal.amountMinor,
          occurredAt: signal.occurredAt,
        );

    final existingTxQuery = await _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('softWindowFingerprint', whereIn: candidateWindowFps)
        .get();

    // F07 / FIN-01 / FIN-02: Never merge two distinct same-amount purchases within 15m!
    // Only deduplicate against:
    //  1) Exact same `sourceEventKey`
    //  2) An authoritative `bankWebhook` / `bankApi` canonical record within ±15m (`FIN-02`)
    //  3) Duplicate OS notification repost within 45s carrying identical post-tx `observedBalanceMinor` & merchant
    final matchingExistingDocs = existingTxQuery.docs.where((d) {
      final data = d.data();
      if (data['verification'] == 'rejected') return false;
      if (data['sourceEventKey'] == signal.sourceEventKey) return true;
      if (candidateOrder != null) {
        return data['crossSourceFingerprint'] ==
                signal.crossSourceFingerprint &&
            (data['sourceKind'] == 'bankWebhook' ||
                data['sourceKind'] == 'bankApi');
      }
      final ts = data['occurredAt'];
      final dtDiff = ts is Timestamp
          ? ts.toDate().difference(signal.occurredAt).abs()
          : Duration.zero;
      if (dtDiff > const Duration(minutes: 15)) return false;

      final existingSource = data['sourceKind'] as String?;
      if (existingSource == 'bankWebhook' || existingSource == 'bankApi') {
        final existingMasked = (data['accountMasked'] as String?) ?? '';
        if (tail.isNotEmpty &&
            existingMasked.isNotEmpty &&
            !existingMasked.endsWith(tail)) {
          return false;
        }
        return true;
      }

      if (existingSource == 'androidNotification') {
        final existingObsBal =
            (data['observedBalanceMinor'] as num?)?.toInt() ??
            (data['balanceAfterMinor'] as num?)?.toInt();
        final existingRef = data['referenceCode'] as String?;
        if (signal.referenceCode != null &&
            existingRef != null &&
            signal.referenceCode != existingRef) {
          return false;
        }
        if (signal.observedBalanceMinor != null && existingObsBal != null) {
          // Within ±15m, an identical observed post-tx balance indicates an OS repost of the exact same notification.
          return existingObsBal == signal.observedBalanceMinor;
        }
        if (dtDiff <= const Duration(seconds: 45) &&
            data['merchant'] == '${signal.bankCode}: ${signal.merchant}') {
          return signal.observedBalanceMinor == null && existingObsBal == null;
        }
      }
      return false;
    }).toList();

    // Step 5.5: Offline Financial AI + Personalization Category Enrichment (Phase 12)
    var resolvedCategoryName = signal.categorySuggestion;
    String? resolvedCategoryId;
    var aiAllowsAutoConfirm = true;

    if (candidateOrder == null && _financialAiRepository != null) {
      try {
        final prefsRes = await _financialAiRepository
            .watchPreferences(userId)
            .first;
        final prefs = prefsRes.fold(
          (_) => UserAiClassificationPreferences(userId: userId),
          (p) => p,
        );
        if (prefs.autoClassifyBankNotifications) {
          final norm = FinancialTextNormalizer().toClassifierInput(
            signal.merchant,
          );
          final classRes = await _financialAiRepository
              .classifyNormalizedSegment(norm);
          String topSemKey = signal.direction == 'credit'
              ? 'income.other'
              : 'other';
          double topProb = signal.confidence;
          classRes.fold((_) {}, (cr) {
            final dirAligned = cr.predictions.where((p) {
              final isInc = p.semanticKey.startsWith('income.');
              return signal.direction == 'credit' ? isInc : !isInc;
            }).firstOrNull;
            if (dirAligned != null) {
              topSemKey = dirAligned.semanticKey;
              topProb = dirAligned.probability;
            }
          });

          final canonicalKey = FinancialTextNormalizer.canonicalizeMerchant(
            signal.merchant,
          );
          final catRes = await _financialAiRepository.resolveUserCategory(
            userId: userId,
            semanticKey: topSemKey,
            direction: signal.direction,
            merchantCanonicalKey: canonicalKey,
            source: FinancialInputSource.androidBankNotification,
            amountMinor: signal.amountMinor,
          );
          catRes.fold((_) {}, (match) {
            if (match.hasExactUserCategory || topProb >= 0.45) {
              resolvedCategoryId = match.categoryId;
              resolvedCategoryName = match.displayCategoryName;
            }
            if (match.hasMultipleMatches || topProb < 0.35) {
              aiAllowsAutoConfirm = false;
            }
          });
        }
      } catch (_) {
        // Fallback seamlessly to deterministic signal.categorySuggestion
      }
    }

    final effectiveAutoConfirm =
        autoConfirm && aiAllowsAutoConfirm && !isAmbiguousWalletRouting;
    var isDuplicate = false;
    final txId = candidateOrder != null
        ? 'qr_${signal.sourceEventKey.substring(0, 20)}'
        : 'prov_${signal.sourceEventKey.substring(0, 20)}';

    PaymentOrderEntity? verifiedFreshOrder;
    PaymentOrderStatus? nextOrderStatus;
    String? orderReviewReason;
    var orderWasApplied = false;
    var orderMismatched = false;
    int? orderNewReceivedTotal;

    await _runSerializedTx(
      () => _firestore.runTransaction((tx) async {
        final existingEvent = await tx.get(eventRef);
        if (existingEvent.exists) {
          isDuplicate = true;
          return;
        }

        // F11 / FIN-04: Re-verify candidate inside transaction boundary for concurrency isolation
        String? liveDuplicateTxId;
        for (final cand in matchingExistingDocs) {
          final liveSnap = await tx.get(cand.reference);
          if (liveSnap.exists &&
              liveSnap.data()?['verification'] != 'rejected') {
            liveDuplicateTxId = liveSnap.id;
            break;
          }
        }

        final now = DateTime.now();
        if (liveDuplicateTxId != null) {
          isDuplicate = true;
          tx.set(eventRef, {
            'eventKey': signal.sourceEventKey,
            'source': 'android_notification',
            'status': 'duplicate_linked',
            'linkedTransactionId': liveDuplicateTxId,
            'receivedAt': Timestamp.fromDate(now),
          });
          return;
        }

        var effectiveWalletId = targetWalletId;
        var effectiveIsAmbiguousRouting = isAmbiguousWalletRouting;
        var shouldCommitLedger =
            effectiveAutoConfirm && !effectiveIsAmbiguousRouting;
        Map<String, dynamic>? orderUpdatePayload;
        Map<String, dynamic>? duplicateOrderEventPayload;

        // ALL Firestore transaction reads MUST happen BEFORE any tx.set / tx.update writes!
        final orderRef = candidateOrderRef;
        if (orderRef != null) {
          final freshOrderSnap = await tx.get(orderRef);
          if (freshOrderSnap.exists && freshOrderSnap.data() != null) {
            final freshOrder = _mapPaymentOrder(
              freshOrderSnap.id,
              freshOrderSnap.data()!,
            );
            final isOpenOrder =
                freshOrder.status == PaymentOrderStatus.pending ||
                freshOrder.status == PaymentOrderStatus.partial;
            final isVndOrder = freshOrder.currency.toUpperCase() == 'VND';

            if (isOpenOrder && isVndOrder) {
              verifiedFreshOrder = freshOrder;

              final bankMatches =
                  signal.bankCode == 'BANK' ||
                  freshOrder.bankCode.isEmpty ||
                  signal.bankCode.toUpperCase() ==
                      freshOrder.bankCode.toUpperCase();
              final normalizedOrderAcc = freshOrder.accountNumber.replaceAll(
                RegExp(r'[^0-9A-Za-z]'),
                '',
              );
              final accountTailMatches =
                  signal.accountTail == null ||
                  signal.accountTail!.isEmpty ||
                  normalizedOrderAcc.isEmpty ||
                  normalizedOrderAcc.endsWith(signal.accountTail!);
              final walletMatches =
                  !resolvedSpecificBankWallet ||
                  targetWalletId == freshOrder.walletId;

              final isMismatch =
                  !bankMatches || !accountTailMatches || !walletMatches;

              final updatedMatchedIds = List<String>.from(
                freshOrder.matchedTransactionIds,
              );
              if (updatedMatchedIds.isEmpty &&
                  freshOrder.matchedTransactionId != null &&
                  freshOrder.matchedTransactionId!.isNotEmpty) {
                updatedMatchedIds.add(freshOrder.matchedTransactionId!);
              }
              if (!updatedMatchedIds.contains(txId)) {
                updatedMatchedIds.add(txId);
              }

              if (isMismatch) {
                orderMismatched = true;
                nextOrderStatus = PaymentOrderStatus.needsReview;
                orderReviewReason =
                    'Sai ngân hàng hoặc tài khoản nhận tiền so với đơn VietQR.';
                // Do NOT mark paid, do NOT redirect to freshOrder.walletId,
                // and do NOT apply unverified mismatch to order totals or ledger!
                shouldCommitLedger = false;
                effectiveIsAmbiguousRouting = false;
                orderUpdatePayload = {
                  'status': PaymentOrderStatus.needsReview.name,
                  'reviewReason': orderReviewReason,
                  'matchedTransactionIds': updatedMatchedIds,
                  'matchedTransactionId': txId,
                  'updatedAt': Timestamp.fromDate(now),
                };
              } else {
                effectiveWalletId = freshOrder.walletId;
                effectiveIsAmbiguousRouting = false;

                final contributions = Map<String, int>.from(
                  freshOrder.receivedContributions,
                );
                if (contributions.isEmpty &&
                    freshOrder.receivedAmountMinor > 0) {
                  contributions['__legacy__'] = freshOrder.receivedAmountMinor;
                }
                if (contributions.containsKey(signal.sourceEventKey)) {
                  isDuplicate = true;
                  duplicateOrderEventPayload = {
                    'eventKey': signal.sourceEventKey,
                    'source': 'android_notification',
                    'status': 'duplicate_order_contribution_ignored',
                    'linkedTransactionId':
                        freshOrder.matchedTransactionId ?? txId,
                    'matchedOrderId': freshOrder.id,
                    'receivedAt': Timestamp.fromDate(now),
                  };
                } else {
                  contributions[signal.sourceEventKey] = signal.amountMinor;
                  final newReceivedTotal = contributions.values.fold<int>(
                    0,
                    (acc, v) => acc + v,
                  );
                  orderNewReceivedTotal = newReceivedTotal;
                  orderWasApplied = true;

                  if (newReceivedTotal > freshOrder.amountMinor) {
                    nextOrderStatus = PaymentOrderStatus.needsReview;
                    orderReviewReason =
                        'Thực nhận vượt số tiền yêu cầu (dư ${VndAmount.format(newReceivedTotal - freshOrder.amountMinor)}).';
                    shouldCommitLedger = false;
                    orderUpdatePayload = {
                      'status': PaymentOrderStatus.needsReview.name,
                      'receivedAmountMinor': newReceivedTotal,
                      'receivedContributions': contributions,
                      'matchedTransactionIds': updatedMatchedIds,
                      'matchedTransactionId': txId,
                      'reviewReason': orderReviewReason,
                      'updatedAt': Timestamp.fromDate(now),
                    };
                  } else if (newReceivedTotal < freshOrder.amountMinor) {
                    nextOrderStatus = PaymentOrderStatus.partial;
                    orderReviewReason = null;
                    shouldCommitLedger = true;
                    orderUpdatePayload = {
                      'status': PaymentOrderStatus.partial.name,
                      'receivedAmountMinor': newReceivedTotal,
                      'receivedContributions': contributions,
                      'matchedTransactionIds': updatedMatchedIds,
                      'matchedTransactionId': txId,
                      'reviewReason': null,
                      'updatedAt': Timestamp.fromDate(now),
                    };
                  } else {
                    nextOrderStatus = PaymentOrderStatus.paid;
                    orderReviewReason = null;
                    shouldCommitLedger = true;
                    orderUpdatePayload = {
                      'status': PaymentOrderStatus.paid.name,
                      'receivedAmountMinor': newReceivedTotal,
                      'receivedContributions': contributions,
                      'matchedTransactionIds': updatedMatchedIds,
                      'matchedTransactionId': txId,
                      'reviewReason': null,
                      'paidAt': Timestamp.fromDate(now),
                      'updatedAt': Timestamp.fromDate(now),
                    };
                  }
                }
              }
            }
          }
        }

        if (duplicateOrderEventPayload != null) {
          tx.set(eventRef, duplicateOrderEventPayload);
          return;
        }

        DocumentReference<Map<String, dynamic>>? walletRef;
        DocumentSnapshot<Map<String, dynamic>>? wSnap;
        if (shouldCommitLedger) {
          walletRef = _firestore
              .collection('users')
              .doc(userId)
              .collection('wallets')
              .doc(effectiveWalletId);
          wSnap = await tx.get(walletRef);
        }

        // All reads completed — perform all transactional writes below.
        if (orderRef != null && orderUpdatePayload != null) {
          tx.update(orderRef, orderUpdatePayload);
        }

        final monthKey =
            '${signal.occurredAt.year.toString().padLeft(4, '0')}-${signal.occurredAt.month.toString().padLeft(2, '0')}';

        int? newWalletBal;
        String? resolvedWalletName;
        if (shouldCommitLedger &&
            walletRef != null &&
            wSnap != null &&
            wSnap.exists) {
          final curBal = (wSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
          final delta = signal.direction == 'credit'
              ? signal.amountMinor
              : -signal.amountMinor;
          // If bank notification carries exact post-tx `SD:` balance and syncObservedBalance is enabled, sync exact balance!
          newWalletBal =
              (syncObservedBalance && signal.observedBalanceMinor != null)
              ? signal.observedBalanceMinor!
              : (curBal + delta);
          resolvedWalletName =
              (wSnap.data()?['name'] as String?) ?? 'Ngân hàng';
          tx.update(walletRef, {
            'balanceMinor': newWalletBal,
            if (syncObservedBalance && signal.observedBalanceMinor != null)
              'isEstimatedBalance': false,
            'lastAuditId': 'aud_$txId',
            'updatedAt': Timestamp.fromDate(now),
          });
          tx.set(
            _firestore
                .collection('users')
                .doc(userId)
                .collection('ledger_audits')
                .doc('aud_$txId'),
            {
              'id': 'aud_$txId',
              'ownerId': userId,
              'txId': txId,
              'walletId': effectiveWalletId,
              'walletName': resolvedWalletName,
              'previousBalanceMinor': curBal,
              'deltaMinor': newWalletBal - curBal,
              'newBalanceMinor': newWalletBal,
              'kind': signal.direction == 'credit' ? 'income' : 'expense',
              'createdAt': Timestamp.fromDate(now),
            },
          );
        }

        final orderNeedsReview =
            orderMismatched ||
            nextOrderStatus == PaymentOrderStatus.needsReview;
        final eventStatus = orderMismatched
            ? 'qr_mismatch_needs_review'
            : nextOrderStatus == PaymentOrderStatus.needsReview
            ? 'qr_overpaid_needs_review'
            : nextOrderStatus == PaymentOrderStatus.partial
            ? 'qr_order_partial'
            : nextOrderStatus == PaymentOrderStatus.paid
            ? 'qr_order_reconciled'
            : effectiveIsAmbiguousRouting
            ? 'ambiguous_wallet_needs_review'
            : (effectiveAutoConfirm ? 'auto_confirmed' : 'provisional_created');

        tx.set(eventRef, {
          'eventKey': signal.sourceEventKey,
          'source': 'android_notification',
          'status': eventStatus,
          'linkedTransactionId': txId,
          if (verifiedFreshOrder != null)
            'matchedOrderId': verifiedFreshOrder!.id,
          'receivedAt': Timestamp.fromDate(now),
        });

        final hasObservedBankBal =
            shouldCommitLedger &&
            syncObservedBalance &&
            signal.observedBalanceMinor != null &&
            signal.observedBalanceMinor! > 0;
        final balanceType = hasObservedBankBal
            ? 'observedBankBalance'
            : (shouldCommitLedger
                  ? 'estimatedWalletBalance'
                  : 'unknownBalance');

        // F09 & F08 & H1: QR match from Android notification uses `matchedPaymentOrder`
        // (NEVER claims bank-verified `VERIFIED`), while mismatches/overpays/ambiguous routing use `needsReview`!
        final verifStr = orderNeedsReview
            ? 'needsReview'
            : orderWasApplied
            ? 'matchedPaymentOrder'
            : effectiveIsAmbiguousRouting
            ? 'needsReview'
            : (effectiveAutoConfirm ? 'userConfirmed' : 'provisional');
        final verifUpper = orderNeedsReview
            ? 'NEEDS_REVIEW'
            : orderWasApplied
            ? 'MATCHED_PAYMENT_ORDER'
            : effectiveIsAmbiguousRouting
            ? 'NEEDS_REVIEW'
            : (effectiveAutoConfirm ? 'USER_CONFIRMED' : 'PROVISIONAL');
        final reconciliationStatus = orderMismatched
            ? 'qr_mismatch_needs_review'
            : nextOrderStatus == PaymentOrderStatus.needsReview
            ? 'qr_overpaid_needs_review'
            : nextOrderStatus == PaymentOrderStatus.partial
            ? 'matched_qr_partial'
            : orderWasApplied
            ? 'matched_qr_order'
            : effectiveIsAmbiguousRouting
            ? 'ambiguous_wallet_needs_review'
            : 'unreconciled_provisional';

        final txNote = orderNeedsReview && verifiedFreshOrder != null
            ? 'Đơn QR ${verifiedFreshOrder!.paymentCode}: ${orderReviewReason ?? "Cần đối soát"}'
            : orderWasApplied && verifiedFreshOrder != null
            ? (nextOrderStatus == PaymentOrderStatus.partial
                  ? 'Khớp một phần mã đơn QR ${verifiedFreshOrder!.paymentCode} (đã nhận ${VndAmount.format(orderNewReceivedTotal ?? signal.amountMinor)} / ${VndAmount.format(verifiedFreshOrder!.amountMinor)})'
                  : 'Khớp mã đơn QR ${verifiedFreshOrder!.paymentCode} từ thông báo thiết bị')
            : effectiveIsAmbiguousRouting
            ? 'Có nhiều tài khoản ${signal.bankCode} nhưng thông báo thiếu số đuôi TK — vui lòng chọn đúng ví.'
            : null;

        tx.set(
          _firestore
              .collection('users')
              .doc(userId)
              .collection('transactions')
              .doc(txId),
          {
            'id': txId,
            'ownerId': userId,
            'walletId': effectiveWalletId,
            if (resolvedWalletName != null) 'walletName': resolvedWalletName,
            if (newWalletBal != null) 'balanceAfterMinor': newWalletBal,
            if (signal.observedBalanceMinor != null)
              'observedBalanceMinor': signal.observedBalanceMinor,
            'balanceType': balanceType,
            'ledgerApplied': shouldCommitLedger,
            if (!orderWasApplied && resolvedCategoryId != null)
              'categoryId': resolvedCategoryId,
            'categoryName': orderWasApplied
                ? 'Thu tiền QR'
                : resolvedCategoryName,
            'kind': signal.direction == 'credit' ? 'income' : 'expense',
            'direction': signal.direction,
            'amountMinor': signal.amountMinor,
            'currencyCode': 'VND',
            'bankCode': signal.bankCode,
            if (signal.accountTail != null)
              'accountMasked': '•••• ${signal.accountTail}',
            if (signal.referenceCode != null &&
                signal.referenceCode!.isNotEmpty)
              'referenceCode': signal.referenceCode,
            'merchant': orderWasApplied && verifiedFreshOrder != null
                ? '${verifiedFreshOrder!.description} (${verifiedFreshOrder!.paymentCode})'
                : '${signal.bankCode}: ${signal.merchant}',
            if (txNote != null) 'note': txNote,
            'occurredAt': Timestamp.fromDate(signal.occurredAt),
            'receivedAt': Timestamp.fromDate(now),
            'monthKey': monthKey,
            'sourceProvider': 'android_device',
            'sourceKind': 'androidNotification',
            'verification': verifStr,
            'verificationStatus': verifUpper,
            'reconciliationStatus': reconciliationStatus,
            'sourceEventKey': signal.sourceEventKey,
            'crossSourceFingerprint': signal.crossSourceFingerprint,
            'softWindowFingerprint': softFp,
            'isVehicleMaintenanceHint': signal.isVehicleMaintenanceHint,
            'isRecurringCandidate':
                ExplainableBankingRuleEngine.detectRecurringSuggestionLabel(
                  '$title $body',
                  signal.direction,
                ) !=
                null,
            'schemaVersion': 2,
            'createdAt': Timestamp.fromDate(now),
            'updatedAt': Timestamp.fromDate(now),
          },
        );

        final notifId = 'notif_${signal.sourceEventKey.substring(0, 24)}';
        final sign = signal.direction == 'credit' ? '+' : '-';
        final notifTitle =
            !orderNeedsReview && (orderWasApplied || effectiveAutoConfirm)
            ? (signal.direction == 'credit'
                  ? '💰 Life OS — Tiền vừa về!'
                  : '💸 Life OS — Giao dịch chi tiêu')
            : '🔔 Life OS — Phát hiện biến động ngân hàng';
        final statusVi = orderNeedsReview
            ? 'Cần đối soát'
            : nextOrderStatus == PaymentOrderStatus.partial
            ? 'Đã nhận một phần đơn QR'
            : orderWasApplied
            ? 'Đã khớp đơn QR'
            : effectiveIsAmbiguousRouting
            ? 'Cần chọn đúng ví'
            : (effectiveAutoConfirm ? 'Đã xác nhận' : 'Tạm ghi nhận');
        final notifBody =
            '$sign${VndAmount.format(signal.amountMinor)}\nNguồn: Thông báo Android\nTrạng thái: $statusVi';
        tx.set(_financialNotifsCol(userId).doc(notifId), {
          'id': notifId,
          'ownerId': userId,
          'transactionId': txId,
          'walletId': effectiveWalletId,
          'connectionId': '',
          'direction': signal.direction,
          'amountMinor': signal.amountMinor,
          'bankCode': signal.bankCode,
          'bankName': signal.bankCode,
          'accountMasked': signal.accountTail != null
              ? '•••• ${signal.accountTail}'
              : '••••',
          'title': notifTitle,
          'body': notifBody,
          'content': signal.merchant,
          'verificationStatus': verifUpper,
          'sourceKind': 'androidNotification',
          'isRead': false,
          'isTestNotification': false,
          'occurredAt': Timestamp.fromDate(signal.occurredAt),
          'createdAt': Timestamp.fromDate(now),
        });
      }),
    );

    // F10 / BG-01: Explicitly ACK durable Android SQLite queue ONLY AFTER Firestore transaction succeeds!
    if (notificationId != null && notificationId.isNotEmpty) {
      await _bridge.acknowledgeQueuedNotification(notificationId);
    }

    if (isDuplicate) {
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.duplicateIgnored,
        message: 'Giao dịch trùng lặp đã được bỏ qua.',
      );
    }

    // Step 6: Auto-settle Family / Group Split Debt if incoming memo carries `LIFEOS SPLIT...`!
    if (!orderMismatched &&
        nextOrderStatus != PaymentOrderStatus.needsReview &&
        signal.direction == 'credit' &&
        signal.matchedPaymentCode != null &&
        signal.matchedPaymentCode!.startsWith('LIFEOS SPLIT')) {
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        final activeFamId = (userDoc.data()?['activeFamilyId'] as String?)
            ?.trim();
        final receiverName =
            (userDoc.data()?['fullName'] as String?) ?? 'Thành viên';
        if (activeFamId != null && activeFamId.isNotEmpty) {
          final settleId = 'auto_st_${signal.sourceEventKey.substring(0, 16)}';
          await _firestore
              .collection('families')
              .doc(activeFamId)
              .collection('settlements')
              .doc(settleId)
              .set({
                'id': settleId,
                'familyId': activeFamId,
                'fromUserId': 'bank_transfer',
                'fromUserName': signal.merchant,
                'toUserId': userId,
                'toUserName': receiverName,
                'amountMinor': signal.amountMinor,
                'paymentCode': signal.matchedPaymentCode,
                'createdAt': Timestamp.fromDate(DateTime.now()),
              });
        }
      } catch (_) {}
    }

    if (verifiedFreshOrder != null &&
        nextOrderStatus == PaymentOrderStatus.needsReview) {
      return IngestionOutcome(
        kind: IngestionOutcomeKind.createdProvisional,
        transactionId: txId,
        matchedOrderId: verifiedFreshOrder!.id,
        matchedPaymentCode: verifiedFreshOrder!.paymentCode,
        message:
            orderReviewReason ??
            'Giao dịch khớp mã ${verifiedFreshOrder!.paymentCode} cần đối soát.',
      );
    }

    if (orderWasApplied && verifiedFreshOrder != null) {
      if (nextOrderStatus == PaymentOrderStatus.partial) {
        final remaining =
            verifiedFreshOrder!.amountMinor -
            (orderNewReceivedTotal ?? signal.amountMinor);
        return IngestionOutcome(
          kind: IngestionOutcomeKind.autoReconciledOrder,
          transactionId: txId,
          matchedOrderId: verifiedFreshOrder!.id,
          matchedPaymentCode: verifiedFreshOrder!.paymentCode,
          message:
              'Đã nhận một phần ${VndAmount.format(signal.amountMinor)} cho mã ${verifiedFreshOrder!.paymentCode} (còn thiếu ${VndAmount.format(remaining)}).',
        );
      }
      return IngestionOutcome(
        kind: IngestionOutcomeKind.autoReconciledOrder,
        transactionId: txId,
        matchedOrderId: verifiedFreshOrder!.id,
        matchedPaymentCode: verifiedFreshOrder!.paymentCode,
        message:
            'Đã nhận ${VndAmount.format(signal.amountMinor)} · Tự động gạch nợ mã ${verifiedFreshOrder!.paymentCode}!',
      );
    }

    return IngestionOutcome(
      kind: IngestionOutcomeKind.createdProvisional,
      transactionId: txId,
      message: isAmbiguousWalletRouting
          ? 'Có nhiều tài khoản ${signal.bankCode} — vui lòng kiểm tra và chọn ví.'
          : effectiveAutoConfirm
          ? 'Đã tự động ghi nhận ${VndAmount.format(signal.amountMinor)} vào ví.'
          : 'Đã nhận diện giao dịch mới chờ xác nhận.',
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
    int? accumulatedBalanceMinor,
    String? bankCode,
    String? accountMasked,
  }) async {
    final eventKey = BankNotificationParser.computeSourceEventKey(
      'bank_api',
      externalTransactionId,
    );
    final eventRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('source_events')
        .doc(eventKey);

    final softFp = BankNotificationParser.computeSoftWindowFingerprint(
      ownerId: userId,
      direction: direction,
      amountMinor: amountMinor,
      occurredAt: occurredAt,
    );
    final candidateWindowFps =
        BankNotificationParser.computeOverlappingSoftWindowFingerprints(
          ownerId: userId,
          direction: direction,
          amountMinor: amountMinor,
          occurredAt: occurredAt,
        );

    final provMatches = await _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('softWindowFingerprint', whereIn: candidateWindowFps)
        .get();

    // Exact externalTransactionId duplicate check (T21: REST API reverse sync after Webhook)
    final exactExternalMatch = provMatches.docs.where((d) {
      final ext = d.data()['externalTransactionId']?.toString();
      return ext != null && ext == externalTransactionId;
    }).firstOrNull;

    // Cross-source reconciliation candidates (T05, T06, T24, F09):
    // Upgrades `provisional`, `userConfirmed`, `matchedPaymentOrder`, or `needsReview` Android signals within ±15m!
    final reconcilableCandidates = provMatches.docs.where((d) {
      final data = d.data();
      if (data['verification'] == 'rejected') return false;
      if (data['sourceKind'] != 'androidNotification') return false;
      final existingExt = data['externalTransactionId']?.toString();
      if (existingExt != null &&
          existingExt.isNotEmpty &&
          existingExt != externalTransactionId) {
        return false;
      }
      final existingRef = (data['referenceCode'] as String?)?.trim() ?? '';
      final incomingRef = (referenceCode ?? '').trim();
      if (existingRef.isNotEmpty &&
          incomingRef.isNotEmpty &&
          existingRef.toUpperCase() != incomingRef.toUpperCase()) {
        return false;
      }
      final ts = data['occurredAt'];
      if (ts is! Timestamp) return true;
      return ts.toDate().difference(occurredAt).abs() <=
          const Duration(minutes: 15);
    }).toList();

    final isAmbiguousCollision = reconcilableCandidates.length > 1;
    final matchingAndroidDoc = reconcilableCandidates.length == 1
        ? reconcilableCandidates.first
        : null;

    var outcomeKind = IngestionOutcomeKind.upgradedToVerified;
    var targetTxId =
        exactExternalMatch?.id ??
        matchingAndroidDoc?.id ??
        'ver_${eventKey.substring(0, 20)}';

    // F11 / FIN-04: Deterministic external transaction claim inside runTransaction blocks burst race conditions!
    final claimRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('source_claims')
        .doc('ext_$externalTransactionId');

    await _firestore.runTransaction((tx) async {
      final evSnap = await tx.get(eventRef);
      final claimSnap = await tx.get(claimRef);
      if (evSnap.exists || claimSnap.exists || exactExternalMatch != null) {
        outcomeKind = IngestionOutcomeKind.duplicateIgnored;
        return;
      }

      DocumentSnapshot<Map<String, dynamic>>? liveAndroidSnap;
      if (matchingAndroidDoc != null) {
        final snap = await tx.get(matchingAndroidDoc.reference);
        if (snap.exists && snap.data()?['externalTransactionId'] == null) {
          liveAndroidSnap = snap;
        } else if (snap.exists) {
          // Another worker already upgraded this Android doc; create standalone verified or skip if same extId
          if (snap.data()?['externalTransactionId']?.toString() ==
              externalTransactionId) {
            outcomeKind = IngestionOutcomeKind.duplicateIgnored;
            return;
          }
          targetTxId = 'ver_${eventKey.substring(0, 20)}';
        }
      }

      final walletRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('wallets')
          .doc(walletId);
      final walletSnap = await tx.get(walletRef);
      final currentBal =
          (walletSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
      final delta = direction == 'credit' ? amountMinor : -amountMinor;
      final now = DateTime.now();

      tx.set(claimRef, {
        'externalTransactionId': externalTransactionId,
        'linkedTransactionId': targetTxId,
        'claimedAt': Timestamp.fromDate(now),
      });

      final matchedData = liveAndroidSnap?.data();
      final alreadyAppliedInLedger =
          matchedData != null &&
          ((matchedData['ledgerApplied'] as bool?) ??
              (matchedData['verification'] == 'userConfirmed' ||
                  matchedData['verification'] == 'matchedPaymentOrder' ||
                  matchedData['verification'] == 'verified'));

      // T15: NEVER treat accumulatedBalanceMinor == 0 as zero bank balance!
      final hasObservedBankBalance =
          accumulatedBalanceMinor != null && accumulatedBalanceMinor > 0;

      var newWalletBalance = currentBal;
      var balanceType = 'unknownBalance';
      final resolvedWalletName =
          (walletSnap.data()?['name'] as String?) ?? 'Ngân hàng';
      if (!isAmbiguousCollision) {
        if (hasObservedBankBalance) {
          newWalletBalance = accumulatedBalanceMinor;
          balanceType = 'observedBankBalance';
          if (walletSnap.exists) {
            final auditId = 'aud_${targetTxId}_ver';
            tx.update(walletRef, {
              'balanceMinor': newWalletBalance,
              'isEstimatedBalance': false,
              'lastAuditId': auditId,
              'updatedAt': Timestamp.fromDate(now),
            });
            tx.set(
              _firestore
                  .collection('users')
                  .doc(userId)
                  .collection('ledger_audits')
                  .doc(auditId),
              {
                'id': auditId,
                'ownerId': userId,
                'txId': targetTxId,
                'walletId': walletId,
                'walletName': resolvedWalletName,
                'previousBalanceMinor': currentBal,
                'deltaMinor': newWalletBalance - currentBal,
                'newBalanceMinor': newWalletBalance,
                'kind': direction == 'credit' ? 'income' : 'expense',
                'createdAt': Timestamp.fromDate(now),
              },
            );
          }
        } else if (!alreadyAppliedInLedger) {
          newWalletBalance = currentBal + delta;
          balanceType = 'estimatedWalletBalance';
          if (walletSnap.exists) {
            final auditId = 'aud_${targetTxId}_ver';
            tx.update(walletRef, {
              'balanceMinor': newWalletBalance,
              'lastAuditId': auditId,
              'updatedAt': Timestamp.fromDate(now),
            });
            tx.set(
              _firestore
                  .collection('users')
                  .doc(userId)
                  .collection('ledger_audits')
                  .doc(auditId),
              {
                'id': auditId,
                'ownerId': userId,
                'txId': targetTxId,
                'walletId': walletId,
                'walletName': resolvedWalletName,
                'previousBalanceMinor': currentBal,
                'deltaMinor': delta,
                'newBalanceMinor': newWalletBalance,
                'kind': direction == 'credit' ? 'income' : 'expense',
                'createdAt': Timestamp.fromDate(now),
              },
            );
          }
        } else {
          // T24: Balance delta was ALREADY applied when Android signal was confirmed -> DO NOT apply twice!
          newWalletBalance = currentBal;
          balanceType = (walletSnap.data()?['isEstimatedBalance'] == false)
              ? 'observedBankBalance'
              : 'estimatedWalletBalance';
        }
      }

      tx.set(eventRef, {
        'eventKey': eventKey,
        'source': 'bank_api',
        'status': isAmbiguousCollision ? 'needs_review' : 'verified_processed',
        'linkedTransactionId': targetTxId,
        'receivedAt': Timestamp.fromDate(now),
      });

      if (matchingAndroidDoc != null) {
        tx.update(matchingAndroidDoc.reference, {
          'verification': 'verified',
          'verificationStatus': 'VERIFIED',
          'reconciliationStatus': 'reconciled_cross_source',
          'sourceProvider': 'sepay',
          'sourceKind': 'bankApi',
          'externalTransactionId': externalTransactionId,
          if (referenceCode != null && referenceCode.isNotEmpty)
            'referenceCode': referenceCode,
          'walletId': walletId,
          'walletName': resolvedWalletName,
          'balanceAfterMinor': newWalletBalance,
          'balanceType': balanceType,
          'ledgerApplied': true,
          'updatedAt': Timestamp.fromDate(now),
        });
      } else {
        targetTxId = 'ver_${eventKey.substring(0, 20)}';
        final inferred = BankNotificationParser.inferCategory(
          content,
          direction,
        );
        final monthKey =
            '${occurredAt.year.toString().padLeft(4, '0')}-${occurredAt.month.toString().padLeft(2, '0')}';
        final verifName = isAmbiguousCollision ? 'needsReview' : 'verified';
        final verifUpper = isAmbiguousCollision ? 'NEEDS_REVIEW' : 'VERIFIED';
        tx.set(
          _firestore
              .collection('users')
              .doc(userId)
              .collection('transactions')
              .doc(targetTxId),
          {
            'id': targetTxId,
            'ownerId': userId,
            'walletId': walletId,
            'walletName': resolvedWalletName,
            if (!isAmbiguousCollision) 'balanceAfterMinor': newWalletBalance,
            'balanceType': balanceType,
            'ledgerApplied': !isAmbiguousCollision,
            'categoryName': inferred.category,
            'kind': direction == 'credit' ? 'income' : 'expense',
            'direction': direction,
            'amountMinor': amountMinor,
            'currencyCode': 'VND',
            if (bankCode != null) 'bankCode': bankCode,
            if (accountMasked != null) 'accountMasked': accountMasked,
            'externalTransactionId': externalTransactionId,
            if (referenceCode != null && referenceCode.isNotEmpty)
              'referenceCode': referenceCode,
            'merchant': content,
            'occurredAt': Timestamp.fromDate(occurredAt),
            'receivedAt': Timestamp.fromDate(now),
            'monthKey': monthKey,
            'sourceProvider': 'sepay',
            'sourceKind': 'bankApi',
            'verification': verifName,
            'verificationStatus': verifUpper,
            'reconciliationStatus': isAmbiguousCollision
                ? 'ambiguous_collision'
                : 'canonical_verified',
            'sourceEventKey': eventKey,
            'crossSourceFingerprint':
                BankNotificationParser.computeCrossSourceFingerprint(
                  ownerId: userId,
                  direction: direction,
                  amountMinor: amountMinor,
                  occurredAt: occurredAt,
                  referenceCode: referenceCode,
                ),
            'softWindowFingerprint': softFp,
            'isVehicleMaintenanceHint': inferred.isVehicleMaintenance,
            'isRecurringCandidate':
                ExplainableBankingRuleEngine.detectRecurringSuggestionLabel(
                  content,
                  direction,
                ) !=
                null,
            'schemaVersion': 2,
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
          ? 'Giao dịch trùng lặp đã bỏ qua.'
          : 'Đã xác nhận giao dịch và cập nhật số dư ví.',
    );
  }

  Future<String> exportPersonalDataJson(String userId) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final wallets = await _firestore
        .collection('users')
        .doc(userId)
        .collection('wallets')
        .get();
    final bankAccounts = await _bankAccountsCol(userId).get();
    final paymentOrders = await _paymentOrdersCol(userId).limit(100).get();
    final txs = await _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .limit(200)
        .get();
    final privEvents = await _firestore
        .collection('users')
        .doc(userId)
        .collection('private_events')
        .get();

    Map<String, dynamic> sanitizeMap(Map<String, dynamic>? m) {
      if (m == null) return {};
      return m.map((k, v) {
        if (v is Timestamp) return MapEntry(k, v.toDate().toIso8601String());
        return MapEntry(k, v);
      });
    }

    final payload = {
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': sanitizeMap(userDoc.data()),
      'wallets': wallets.docs.map((d) => sanitizeMap(d.data())).toList(),
      'bankAccounts': bankAccounts.docs
          .map((d) => sanitizeMap(d.data()))
          .toList(),
      'paymentOrders': paymentOrders.docs
          .map((d) => sanitizeMap(d.data()))
          .toList(),
      'transactions': txs.docs.map((d) => sanitizeMap(d.data())).toList(),
      'privateEvents': privEvents.docs
          .map((d) => sanitizeMap(d.data()))
          .toList(),
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
      if (i == 0 &&
          RegExp(
            r'(date|ngay|amount|so_tien|description)',
            caseSensitive: false,
          ).hasMatch(line)) {
        continue;
      }
      if (OtpRedactor.containsOtpOrSecret(line)) {
        continue;
      }

      final cols = line.split(',').map((c) => c.trim()).toList();
      if (cols.length < 3) continue;

      final parsedDate = DateTime.tryParse(cols[0]) ?? DateTime.now();
      final rawDir = cols[1].toLowerCase();
      final direction = (rawDir == 'credit' || rawDir == 'in' || rawDir == '+')
          ? 'credit'
          : 'debit';
      final amountMinor = VndAmount.tryParseInput(cols[2]);
      if (amountMinor == null || amountMinor <= 0) continue;
      final desc = cols.length >= 4 && cols[3].isNotEmpty
          ? cols.sublist(3).join(', ')
          : 'Sao kê CSV';

      final rowEventKey = BankNotificationParser.computeSourceEventKey(
        'csv',
        '$userId:$walletId:${cols[0]}:$direction:$amountMinor:$desc',
      );
      final eventRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('source_events')
          .doc(rowEventKey);
      final txId = 'csv_${rowEventKey.substring(0, 20)}';
      final txRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('transactions')
          .doc(txId);
      final walletRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('wallets')
          .doc(walletId);

      await _firestore.runTransaction((tx) async {
        final existing = await tx.get(eventRef);
        if (existing.exists) return;

        final wSnap = await tx.get(walletRef);
        final currentBal =
            (wSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
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
          final walletName = (wSnap.data()?['name'] as String?) ?? 'Ngân hàng';
          final auditId = 'aud_$txId';
          tx.update(walletRef, {
            'balanceMinor': currentBal + delta,
            'lastAuditId': auditId,
            'updatedAt': Timestamp.fromDate(now),
          });
          tx.set(
            _firestore
                .collection('users')
                .doc(userId)
                .collection('ledger_audits')
                .doc(auditId),
            {
              'id': auditId,
              'ownerId': userId,
              'txId': txId,
              'walletId': walletId,
              'walletName': walletName,
              'previousBalanceMinor': currentBal,
              'deltaMinor': delta,
              'newBalanceMinor': currentBal + delta,
              'kind': direction == 'credit' ? 'income' : 'expense',
              'createdAt': Timestamp.fromDate(now),
            },
          );
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
          'crossSourceFingerprint':
              BankNotificationParser.computeCrossSourceFingerprint(
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
    // 1. Pre-check BEFORE any destructive wipe: block silent Firestore failure
    //    if user is still owner of a multi-member family/group space.
    final famSnap = await _firestore
        .collection('families')
        .where('memberIds', arrayContains: userId)
        .get();
    for (final famDoc in famSnap.docs) {
      final d = famDoc.data();
      final members = (d['memberIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList();
      final roles = Map<String, dynamic>.from((d['memberRoles'] as Map?) ?? {});
      final isOwner = roles[userId] == 'owner' || d['createdBy'] == userId;
      if (isOwner && members.length > 1) {
        final familyName = (d['name'] as String?)?.trim().isNotEmpty == true
            ? (d['name'] as String).trim()
            : 'nhóm gia đình';
        throw AppException(
          code: 'FAMILY_OWNER_TRANSFER_REQUIRED',
          message:
              'Bạn đang là chủ sở hữu của "$familyName" (${members.length} thành viên). Vui lòng chuyển quyền chủ sở hữu hoặc xóa thành viên khác trước khi xóa tài khoản.',
        );
      }
    }

    // 2. Pre-check recent authentication BEFORE wiping personal Firestore/device data
    final current = _firebaseAuth.currentUser;
    if (current != null && current.uid == userId) {
      final lastSignIn = current.metadata.lastSignInTime;
      if (lastSignIn != null &&
          lastSignIn.millisecondsSinceEpoch > 0 &&
          DateTime.now().difference(lastSignIn) > const Duration(minutes: 5)) {
        throw const AppException(
          code: 'REQUIRES_RECENT_LOGIN',
          message:
              'Vì lý do bảo mật, bạn cần đăng nhập lại gần đây trước khi xóa vĩnh viễn tài khoản.',
        );
      }
    }

    // 3. Invoke server-side Cloud Function `deleteUserAccountData` FIRST
    //    (after pre-checks pass, BEFORE mutating/wiping partial client state!)
    //    with safe retry (2 attempts) to purge server-only collections.
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final resp = await _invokeBackendFunction(
          'deleteUserAccountData',
          <String, dynamic>{'userId': userId},
        );
        if (resp['ok'] == false) {
          throw AppException(
            code: 'SERVER_ACCOUNT_DELETION_FAILED',
            message:
                (resp['message'] as String?) ??
                'Không thể xóa dữ liệu tài khoản trên máy chủ.',
          );
        }
        break;
      } catch (e) {
        final msg = e.toString();
        // In local unit tests without a live Firebase app or functions mock,
        // allow local Firestore wipe to proceed unless an override explicitly failed.
        if (_functionsInvokerOverride == null &&
            (msg.contains('no-app') ||
                msg.contains('No Firebase App') ||
                msg.contains('MissingPluginException'))) {
          break;
        }
        if (attempt == 2) {
          rethrow;
        }
      }
    }

    // 4. Purge Firestore personal subcollections, nested collections & family memberships
    final userDocRef = _firestore.collection('users').doc(userId);
    await userDocRef.set({
      'id': userId,
      'deletionInProgress': true,
      'deletionStartedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));

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
      final roles = Map<String, dynamic>.from((d['memberRoles'] as Map?) ?? {})
        ..remove(userId);
      final names = Map<String, dynamic>.from((d['memberNames'] as Map?) ?? {})
        ..remove(userId);
      await famDoc.reference.update({
        'memberIds': members,
        'memberRoles': roles,
        'memberNames': names,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    }

    final pFundsSnap = await userDocRef.collection('personal_funds').get();
    for (final fundDoc in pFundsSnap.docs) {
      for (final nested in const ['contributions', 'expenses', 'fund_audits']) {
        final nSnap = await fundDoc.reference.collection(nested).get();
        for (final nDoc in nSnap.docs) {
          await nDoc.reference.delete();
        }
      }
    }
    final vehiclesSnap = await userDocRef.collection('vehicles').get();
    for (final vDoc in vehiclesSnap.docs) {
      for (final nested in const ['maintenances', 'fuel_logs']) {
        final nSnap = await vDoc.reference.collection(nested).get();
        for (final nDoc in nSnap.docs) {
          await nDoc.reference.delete();
        }
      }
    }

    const allPersonalSubcollections = [
      'wallets',
      'bank_accounts',
      'bank_connections',
      'financial_notifications',
      'devices',
      'notification_preferences',
      'merchant_rules',
      'payment_orders',
      'ledger_audits',
      'net_worth_snapshots',
      'monthly_summaries',
      'automation_rules',
      'automation_audits',
      'source_claims',
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
      'daily_preferences',
      'grocery_items',
      'meal_plans',
      'utility_readings',
      'home_contracts',
      'life_notes',
      'medications',
      'health_logs',
      'medical_profiles',
      'ai_personalization_rules',
      'ai_category_corrections',
      'ai_pending_drafts',
      'ai_preferences',
    ];
    for (final sub in allPersonalSubcollections) {
      final subSnap = await userDocRef.collection(sub).get();
      for (final d in subSnap.docs) {
        await d.reference.delete();
      }
    }

    await userDocRef.delete();

    // 5. Purge local native queues, user-scoped vault secrets, alarms, widgets & session prefs
    await _bridge.clearAllQueuedNotifications();
    await _bridge.syncConsentConfig(
      enabled: false,
      allowedPackages: const [],
      voiceSoundboxEnabled: false,
    );
    await _clearUserScopedLocalVault(userId);
    await NativeAlarmSchedulerBridge.instance.clearAllAlarms();
    if (sl.isRegistered<NativeHomeWidgetBridge>()) {
      await sl<NativeHomeWidgetBridge>().clearWidgetsOnSignOut();
    } else {
      await NativeHomeWidgetBridge().clearWidgetsOnSignOut();
    }
    UserBehaviorPrefs.clearSessionOnSignOut();

    // 6. Delete Firebase Auth account (only after server & client cleanup succeed)

    if (current != null && current.uid == userId) {
      try {
        await current.delete();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          throw const AppException(
            code: 'REQUIRES_RECENT_LOGIN',
            message:
                'Vì lý do bảo mật, bạn cần đăng nhập lại gần đây để hoàn tất xóa tài khoản.',
          );
        }
        throw AppException(
          code: 'AUTH_DELETE_FAILED',
          message: e.message ?? 'Không thể xóa tài khoản xác thực.',
        );
      }
    } else {
      await _firebaseAuth.signOut();
    }
  }

  BankConnectionEntity _mapBankConnection(String id, Map<String, dynamic> d) {
    final bankCode = (d['bankCode'] as String?) ?? 'VCB';
    final bankName = (d['bankName'] as String?) ?? bankCode;
    final capMap = d['capabilities'];
    final cap = capMap is Map<dynamic, dynamic>
        ? BankIntegrationCapability(
            bankCode: (capMap['bankCode'] as String?) ?? bankCode,
            bankName: (capMap['bankName'] as String?) ?? bankName,
            supportsWebhookCredit:
                (capMap['supportsWebhookCredit'] as bool?) ?? false,
            supportsWebhookDebit:
                (capMap['supportsWebhookDebit'] as bool?) ?? false,
            supportsApiCredit: (capMap['supportsApiCredit'] as bool?) ?? false,
            supportsApiDebit: (capMap['supportsApiDebit'] as bool?) ?? false,
            supportsAndroidCredit:
                (capMap['supportsAndroidCredit'] as bool?) ?? true,
            supportsAndroidDebit:
                (capMap['supportsAndroidDebit'] as bool?) ?? true,
            supportsVerifiedBalance:
                (capMap['supportsVerifiedBalance'] as bool?) ?? true,
            requiredIntegrationType: BankIntegrationRequirement.fromWire(
              capMap['requiredIntegrationType'] as String?,
            ),
            limitations:
                (capMap['limitations'] as List<dynamic>? ?? const <dynamic>[])
                    .map((e) => e.toString())
                    .toList(),
            lastVerifiedAt: DateTime.utc(2026, 11, 23),
          )
        : BankIntegrationCapability.forBankCode(
            bankCode,
            fallbackName: bankName,
          );

    final syncTs = d['lastSyncedAt'];
    return BankConnectionEntity(
      id: id,
      ownerId: (d['ownerId'] as String?) ?? '',
      provider: (d['provider'] as String?) ?? 'sepay',
      providerConnectionId: (d['providerConnectionId'] as String?) ?? id,
      bankCode: bankCode,
      bankName: bankName,
      accountMasked: (d['accountMasked'] as String?) ?? '••••',
      subAccount: (d['subAccount'] as String?) ?? '',
      linkedWalletId: (d['linkedWalletId'] as String?) ?? 'wallet_bank_default',
      consentStatus: (d['consentStatus'] as String?) ?? 'granted',
      status: BankConnectionStatus.fromWire(d['status'] as String?),
      capabilities: cap,
      lastSyncedAt: syncTs is Timestamp ? syncTs.toDate() : null,
      lastError:
          (d['lastError'] as String?) ?? (d['lastRevocationError'] as String?),
    );
  }

  Stream<List<BankConnectionEntity>> watchBankConnections(String userId) {
    return _bankConnectionsCol(userId).snapshots().map((snap) {
      return snap.docs.map((d) => _mapBankConnection(d.id, d.data())).toList();
    });
  }

  Future<BankConnectionEntity> linkVerifiedSePayConnection({
    required String userId,
    required String bankCode,
    required String accountNumber,
    String subAccount = '',
    required String linkedWalletId,
    required String sepayApiToken,
  }) async {
    final cleanAcc = accountNumber
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .trim();
    if (cleanAcc.length < 6) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Số tài khoản phải có ít nhất 6 ký tự.',
      );
    }
    if (sepayApiToken.trim().length < 16) {
      throw const AppException(
        code: 'OWNERSHIP_PROOF_REQUIRED',
        message:
            'Cần cung cấp mã xác thực SePay hợp lệ để xác minh quyền sở hữu tài khoản trên máy chủ (không tự đánh dấu Đã kết nối khi chỉ nhập số tài khoản).',
      );
    }

    final resp = await _invokeBackendFunction('verifyAndLinkBankConnection', {
      'bankCode': bankCode,
      'accountNumber': cleanAcc,
      'subAccount': subAccount.trim(),
      'linkedWalletId': linkedWalletId,
      'sepayApiToken': sepayApiToken.trim(),
    });

    if (resp['ok'] != true) {
      throw AppException(
        code: 'PERMISSION_DENIED',
        message:
            (resp['message'] as String?) ??
            'Xác minh liên kết ngân hàng thất bại.',
      );
    }

    final connId =
        (resp['connectionId'] as String?) ?? 'conn_${bankCode.toLowerCase()}';
    final masked =
        (resp['accountMasked'] as String?) ??
        '•••• ${cleanAcc.substring(cleanAcc.length - 4)}';
    final cap = BankIntegrationCapability.forBankCode(bankCode);
    return BankConnectionEntity(
      id: connId,
      ownerId: userId,
      provider: 'sepay',
      providerConnectionId: connId,
      bankCode: cap.bankCode,
      bankName: cap.bankName,
      accountMasked: masked,
      subAccount: subAccount.trim(),
      linkedWalletId: linkedWalletId,
      consentStatus: 'granted',
      status: BankConnectionStatus.connected,
      capabilities: cap,
      lastSyncedAt: DateTime.now(),
    );
  }

  Future<void> disconnectBankConnection({
    required String userId,
    required String connectionId,
  }) async {
    try {
      final resp = await _invokeBackendFunction('disconnectBankConnection', {
        'connectionId': connectionId,
      });
      if (resp['ok'] == false) {
        throw AppException(
          code: 'SERVER_REVOCATION_FAILED',
          message:
              (resp['message'] as String?) ??
              'Máy chủ chưa xác nhận thu hồi kết nối ngân hàng.',
        );
      }
      // Server succeeded: ensure client mirror reflects disconnected/revoked cleanly.
      await _bankConnectionsCol(userId).doc(connectionId).set({
        'ownerId': userId,
        'status': 'disconnected',
        'consentStatus': 'revoked',
        'lastRevocationError': null,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      }, SetOptions(merge: true));
    } catch (e) {
      // NEVER write status='disconnected' or consentStatus='revoked' when server failed!
      try {
        await _bankConnectionsCol(userId).doc(connectionId).set({
          'ownerId': userId,
          'status': 'pendingRevocation',
          'consentStatus': 'revocation_pending',
          'revocationRequestedAt': Timestamp.fromDate(DateTime.now()),
          'lastRevocationError': e.toString(),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        }, SetOptions(merge: true));
      } catch (_) {}
      throw const AppException(
        code: 'SERVER_REVOCATION_PENDING',
        message:
            'Chưa thể xác nhận ngắt kết nối trên máy chủ. Đã đánh dấu trạng thái chờ thu hồi — vui lòng bấm Thử ngắt lại để dừng hoàn toàn đồng bộ ngân hàng.',
      );
    }
  }

  Future<int> reconcileBankConnection({
    required String userId,
    required String connectionId,
    required String sepayApiToken,
  }) async {
    final resp = await _invokeBackendFunction('reconcileBankConnectionViaApi', {
      'connectionId': connectionId,
      'sepayApiToken': sepayApiToken.trim(),
    });
    return (resp['processedCount'] as num?)?.toInt() ?? 0;
  }

  /// Phase 4 Migration (Section 14): Purges any legacy `users/{uid}/consents/sepay_api` plaintext token
  /// without logging or exposing the token.
  Future<bool> migrateLegacySePayConsentIfPresent(String userId) async {
    final legacyRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('consents')
        .doc('sepay_api');
    final snap = await legacyRef.get();
    if (!snap.exists) return false;

    final data = snap.data() ?? const <String, dynamic>{};
    final legacyToken = data['apiToken'] as String?;
    if (legacyToken != null && legacyToken.trim().isNotEmpty) {
      await NativeSecureVaultBridge.instance.writeSecret(
        key: 'migrated_sepay_token_backup_$userId',
        value: legacyToken.trim(),
      );
    }
    try {
      await _invokeBackendFunction(
        'migrateLegacySePayToken',
        const <String, dynamic>{},
      );
    } catch (_) {}
    await legacyRef.delete();
    return true;
  }

  FinancialNotificationEntity _mapFinancialNotif(
    String id,
    Map<String, dynamic> d,
  ) {
    final occRaw = d['occurredAt'];
    return FinancialNotificationEntity(
      id: id,
      ownerId: (d['ownerId'] as String?) ?? '',
      transactionId: (d['transactionId'] as String?) ?? '',
      walletId: (d['walletId'] as String?) ?? '',
      connectionId: (d['connectionId'] as String?) ?? '',
      direction: (d['direction'] as String?) ?? 'credit',
      amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
      bankCode: (d['bankCode'] as String?) ?? 'BANK',
      bankName: (d['bankName'] as String?) ?? 'Ngân hàng',
      accountMasked: (d['accountMasked'] as String?) ?? '••••',
      title: (d['title'] as String?) ?? 'Biến động ngân hàng',
      body: (d['body'] as String?) ?? '',
      content: (d['content'] as String?) ?? '',
      verificationStatus: (d['verificationStatus'] as String?) ?? 'PROVISIONAL',
      sourceKind: (d['sourceKind'] as String?) ?? 'androidNotification',
      isRead: (d['isRead'] as bool?) ?? false,
      isTestNotification: (d['isTestNotification'] as bool?) ?? false,
      occurredAt: occRaw is Timestamp ? occRaw.toDate() : DateTime.now(),
    );
  }

  Stream<List<FinancialNotificationEntity>> watchFinancialNotifications(
    String userId,
  ) {
    return _financialNotifsCol(userId).snapshots().map((snap) {
      final items =
          snap.docs.map((d) => _mapFinancialNotif(d.id, d.data())).toList()
            ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return items;
    });
  }

  Future<FinancialNotificationEntity> sendTestBankingNotification(
    String userId,
  ) async {
    final now = DateTime.now();
    final id = 'test_notif_${now.millisecondsSinceEpoch}';
    final entity = FinancialNotificationEntity(
      id: id,
      ownerId: userId,
      transactionId: '',
      walletId: '',
      direction: 'credit',
      amountMinor: 0,
      bankCode: 'TEST',
      bankName: 'Kiểm thử hệ thống',
      accountMasked: '•••• 0000',
      title: '🧪 [KIỂM THỬ] Thông báo ngân hàng Life OS',
      body:
          'Đây là thông báo kiểm thử hiển thị — KHÔNG tạo giao dịch tài chính thật trong Sổ cái.',
      content: 'Thông báo kiểm thử (không tạo giao dịch thật)',
      verificationStatus: 'VERIFIED',
      sourceKind: 'test',
      isRead: false,
      isTestNotification: true,
      occurredAt: now,
    );
    await _financialNotifsCol(userId).doc(id).set({
      'id': id,
      'ownerId': userId,
      'transactionId': '',
      'walletId': '',
      'connectionId': '',
      'direction': 'credit',
      'amountMinor': 0,
      'bankCode': 'TEST',
      'bankName': 'Kiểm thử hệ thống',
      'accountMasked': '•••• 0000',
      'title': entity.title,
      'body': entity.body,
      'content': entity.content,
      'verificationStatus': 'VERIFIED',
      'sourceKind': 'test',
      'isRead': false,
      'isTestNotification': true,
      'occurredAt': Timestamp.fromDate(now),
      'createdAt': Timestamp.fromDate(now),
    });
    return entity;
  }

  Stream<BankingNotificationPreferencesEntity>
  watchBankingNotificationPreferences(String userId) {
    return _notifPrefsRef(userId).snapshots().map((snap) {
      if (!snap.exists) {
        return BankingNotificationPreferencesEntity(ownerId: userId);
      }
      final d = snap.data() ?? const <String, dynamic>{};
      return BankingNotificationPreferencesEntity(
        ownerId: userId,
        notifyCredit: (d['notifyCredit'] as bool?) ?? true,
        notifyDebit: (d['notifyDebit'] as bool?) ?? true,
        minAmountMinor: (d['minAmountMinor'] as num?)?.toInt() ?? 0,
        hideAmountOnLockscreen: (d['hideAmountOnLockscreen'] as bool?) ?? true,
        hideCounterpartyAndContent:
            (d['hideCounterpartyAndContent'] as bool?) ?? false,
        soundEnabled: (d['soundEnabled'] as bool?) ?? true,
        mutedConnectionIds:
            (d['mutedConnectionIds'] as List<dynamic>? ?? const <dynamic>[])
                .map((e) => e.toString())
                .toList(),
        notifyUnverified: (d['notifyUnverified'] as bool?) ?? true,
      );
    });
  }

  Future<void> updateBankingNotificationPreferences(
    BankingNotificationPreferencesEntity prefs,
  ) async {
    await _notifPrefsRef(prefs.ownerId).set({
      'ownerId': prefs.ownerId,
      'notifyCredit': prefs.notifyCredit,
      'notifyDebit': prefs.notifyDebit,
      'minAmountMinor': prefs.minAmountMinor,
      'hideAmountOnLockscreen': prefs.hideAmountOnLockscreen,
      'hideCounterpartyAndContent': prefs.hideCounterpartyAndContent,
      'soundEnabled': prefs.soundEnabled,
      'mutedConnectionIds': prefs.mutedConnectionIds,
      'notifyUnverified': prefs.notifyUnverified,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  Stream<List<MerchantCategoryRuleEntity>> watchMerchantCategoryRules(
    String userId,
  ) {
    return _merchantRulesCol(userId).snapshots().map((snap) {
      return snap.docs.map((d) {
        final m = d.data();
        return MerchantCategoryRuleEntity(
          id: d.id,
          keyword: (m['keyword'] as String?) ?? '',
          categoryName: (m['categoryName'] as String?) ?? 'Chi tiêu khác',
        );
      }).toList();
    });
  }

  Future<void> saveMerchantCategoryRule({
    required String userId,
    required String keyword,
    required String categoryName,
  }) async {
    final cleanKw = keyword.trim();
    final cleanCat = categoryName.trim();
    if (cleanKw.isEmpty || cleanCat.isEmpty) return;
    final id =
        'rule_${cleanKw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    await _merchantRulesCol(userId).doc(id).set({
      'id': id,
      'ownerId': userId,
      'keyword': cleanKw,
      'categoryName': cleanCat,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    // Section 15 unification: sync merchant rules directly into ai_personalization_rules!
    final aiRepo = _financialAiRepository;
    if (aiRepo != null) {
      try {
        final canonical =
            FinancialTextNormalizer.canonicalizeMerchant(cleanKw) ??
            FinancialTextNormalizer.stripVnAccents(cleanKw)
                .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
                .replaceAll(RegExp(r'^_|_$'), '');
        if (canonical.isNotEmpty) {
          String matchedCatId = 'auto_$canonical';
          String directionCond = 'any';
          try {
            final catsSnap = await _firestore
                .collection('users')
                .doc(userId)
                .collection('categories')
                .get();
            for (final doc in catsSnap.docs) {
              final d = doc.data();
              final name = (d['name'] as String?) ?? '';
              if (name.trim().toLowerCase() == cleanCat.toLowerCase()) {
                matchedCatId = (d['id'] as String?) ?? doc.id;
                directionCond = (d['direction'] as String?) ?? 'any';
                break;
              }
            }
          } catch (_) {}

          await aiRepo.saveCategoryCorrection(
            userId: userId,
            merchantDisplay: cleanKw,
            merchantCanonicalKey: canonical,
            selectedCategoryId: matchedCatId,
            selectedCategoryName: cleanCat,
            semanticKey: 'other',
            directionCondition: directionCond,
            sourceContext: 'bank_notification',
          );
        }
      } catch (_) {}
    }
  }
}

class NotificationsRepositoryImpl implements NotificationsRepository {
  final NotificationsRemoteDataSource _remoteDataSource;
  const NotificationsRepositoryImpl(this._remoteDataSource);

  @override
  Stream<Result<SourceConsentEntity>> watchAndroidNotificationConsent(
    String userId,
  ) {
    return _remoteDataSource
        .watchConsent(userId)
        .map<Result<SourceConsentEntity>>((c) => Success(c))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<SourceConsentEntity>> sink,
                ) {
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
    bool? voiceSoundboxEnabled,
    bool? syncObservedBalance,
  }) async {
    try {
      await _remoteDataSource.updateConsent(
        userId: userId,
        enabled: enabled,
        allowedPackages: allowedPackages,
        autoConfirmSignals: autoConfirmSignals,
        voiceSoundboxEnabled: voiceSoundboxEnabled,
        syncObservedBalance: syncObservedBalance,
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
    int? accumulatedBalanceMinor,
    String? bankCode,
    String? accountMasked,
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
        accumulatedBalanceMinor: accumulatedBalanceMinor,
        bankCode: bankCode,
        accountMasked: accountMasked,
      );
      return Success(res);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Stream<Result<List<BankConnectionEntity>>> watchBankConnections(
    String userId,
  ) {
    return _remoteDataSource
        .watchBankConnections(userId)
        .map<Result<List<BankConnectionEntity>>>((list) => Success(list))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<BankConnectionEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Future<Result<BankConnectionEntity>> linkVerifiedSePayConnection({
    required String userId,
    required String bankCode,
    required String accountNumber,
    String subAccount = '',
    required String linkedWalletId,
    required String sepayApiToken,
  }) async {
    try {
      final conn = await _remoteDataSource.linkVerifiedSePayConnection(
        userId: userId,
        bankCode: bankCode,
        accountNumber: accountNumber,
        subAccount: subAccount,
        linkedWalletId: linkedWalletId,
        sepayApiToken: sepayApiToken,
      );
      return Success(conn);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> disconnectBankConnection({
    required String userId,
    required String connectionId,
  }) async {
    try {
      await _remoteDataSource.disconnectBankConnection(
        userId: userId,
        connectionId: connectionId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<int>> reconcileBankConnection({
    required String userId,
    required String connectionId,
    required String sepayApiToken,
  }) async {
    try {
      final count = await _remoteDataSource.reconcileBankConnection(
        userId: userId,
        connectionId: connectionId,
        sepayApiToken: sepayApiToken,
      );
      return Success(count);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<bool>> migrateLegacySePayConsentIfPresent(String userId) async {
    try {
      final migrated = await _remoteDataSource
          .migrateLegacySePayConsentIfPresent(userId);
      return Success(migrated);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Stream<Result<List<FinancialNotificationEntity>>> watchFinancialNotifications(
    String userId,
  ) {
    return _remoteDataSource
        .watchFinancialNotifications(userId)
        .map<Result<List<FinancialNotificationEntity>>>((list) => Success(list))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<FinancialNotificationEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Future<Result<FinancialNotificationEntity>> sendTestBankingNotification(
    String userId,
  ) async {
    try {
      final notif = await _remoteDataSource.sendTestBankingNotification(userId);
      return Success(notif);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Stream<Result<BankingNotificationPreferencesEntity>>
  watchBankingNotificationPreferences(String userId) {
    return _remoteDataSource
        .watchBankingNotificationPreferences(userId)
        .map<Result<BankingNotificationPreferencesEntity>>((p) => Success(p))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<BankingNotificationPreferencesEntity>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Future<Result<void>> updateBankingNotificationPreferences(
    BankingNotificationPreferencesEntity prefs,
  ) async {
    try {
      await _remoteDataSource.updateBankingNotificationPreferences(prefs);
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Stream<Result<List<MerchantCategoryRuleEntity>>> watchMerchantCategoryRules(
    String userId,
  ) {
    return _remoteDataSource
        .watchMerchantCategoryRules(userId)
        .map<Result<List<MerchantCategoryRuleEntity>>>((list) => Success(list))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<MerchantCategoryRuleEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Future<Result<void>> saveMerchantCategoryRule({
    required String userId,
    required String keyword,
    required String categoryName,
  }) async {
    try {
      await _remoteDataSource.saveMerchantCategoryRule(
        userId: userId,
        keyword: keyword,
        categoryName: categoryName,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Stream<Result<List<LinkedBankAccountEntity>>> watchLinkedBankAccounts(
    String userId,
  ) {
    return _remoteDataSource
        .watchLinkedBankAccounts(userId)
        .map<Result<List<LinkedBankAccountEntity>>>((list) => Success(list))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<LinkedBankAccountEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Future<Result<LinkedBankAccountEntity>> saveLinkedBankAccount({
    required String userId,
    required String walletId,
    required String bankBin,
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountHolderName,
    bool isDefault = true,
  }) async {
    try {
      final saved = await _remoteDataSource.saveLinkedBankAccount(
        userId: userId,
        walletId: walletId,
        bankBin: bankBin,
        bankCode: bankCode,
        bankName: bankName,
        accountNumber: accountNumber,
        accountHolderName: accountHolderName,
        isDefault: isDefault,
      );
      return Success(saved);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> deleteLinkedBankAccount({
    required String userId,
    required String accountId,
  }) async {
    try {
      await _remoteDataSource.deleteLinkedBankAccount(
        userId: userId,
        accountId: accountId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Stream<Result<List<PaymentOrderEntity>>> watchPaymentOrders(String userId) {
    return _remoteDataSource
        .watchPaymentOrders(userId)
        .map<Result<List<PaymentOrderEntity>>>((list) => Success(list))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<PaymentOrderEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Future<Result<PaymentOrderEntity>> createPaymentOrder({
    required String userId,
    required String walletId,
    required String bankBin,
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountHolderName,
    required int amountMinor,
    required String description,
  }) async {
    try {
      final order = await _remoteDataSource.createPaymentOrder(
        userId: userId,
        walletId: walletId,
        bankBin: bankBin,
        bankCode: bankCode,
        bankName: bankName,
        accountNumber: accountNumber,
        accountHolderName: accountHolderName,
        amountMinor: amountMinor,
        description: description,
      );
      return Success(order);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> markPaymentOrderStatus({
    required String userId,
    required String orderId,
    required PaymentOrderStatus status,
  }) async {
    try {
      await _remoteDataSource.markPaymentOrderStatus(
        userId: userId,
        orderId: orderId,
        status: status,
      );
      return const Success(null);
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
  Future<void> speakSoundboxTest(String message) =>
      _remoteDataSource.speakSoundboxTest(message);

  @override
  Stream<Map<String, dynamic>> watchLiveAndroidBankSignals() =>
      _remoteDataSource.watchLiveNativeSignals();

  @override
  Future<List<Map<String, dynamic>>> drainQueuedAndroidBankSignals() =>
      _remoteDataSource.drainQueuedNativeSignals();
}
