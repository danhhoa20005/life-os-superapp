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
import '../../../../core/utils/vietqr_emv_builder.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../domain/entities/notification_entities.dart';
import '../../domain/repositories/notifications_repository.dart';

class NotificationsRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;
  final AndroidNotificationBridge _bridge;

  NotificationsRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseAuth firebaseAuth,
    required AndroidNotificationBridge bridge,
  })  : _firestore = firestore,
        _firebaseAuth = firebaseAuth,
        _bridge = bridge;

  Future<bool> isNativePermissionGranted() => _bridge.isNotificationAccessGranted();

  Future<void> openNativePermissionSettings() => _bridge.openNotificationAccessSettings();

  Future<void> speakSoundboxTest(String message) =>
      _bridge.speakSoundboxAnnouncement(message);

  Stream<Map<String, dynamic>> watchLiveNativeSignals() =>
      _bridge.watchIncomingBankNotifications();

  Future<List<Map<String, dynamic>>> drainQueuedNativeSignals() =>
      _bridge.drainQueuedBackgroundNotifications();

  DocumentReference<Map<String, dynamic>> _consentRef(String userId) =>
      _firestore.collection('users').doc(userId).collection('consents').doc('android_notification');

  CollectionReference<Map<String, dynamic>> _bankAccountsCol(String userId) =>
      _firestore.collection('users').doc(userId).collection('bank_accounts');

  CollectionReference<Map<String, dynamic>> _paymentOrdersCol(String userId) =>
      _firestore.collection('users').doc(userId).collection('payment_orders');

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
    final now = DateTime.now();
    final batch = _firestore.batch();
    batch.set(
      _consentRef(userId),
      {
        'sourceId': 'android_notification',
        'ownerId': userId,
        'enabled': enabled,
        if (autoConfirmSignals != null) 'autoConfirmSignals': autoConfirmSignals,
        if (voiceSoundboxEnabled != null) 'voiceSoundboxEnabled': voiceSoundboxEnabled,
        if (syncObservedBalance != null) 'syncObservedBalance': syncObservedBalance,
        'allowedPackages': allowedPackages,
        'updatedAt': Timestamp.fromDate(now),
      },
      SetOptions(merge: true),
    );

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
      allowedPackages: allowedPackages,
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
      final items = snap.docs.map((d) => _mapBankAccount(d.id, d.data())).toList()
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
    final cleanAcc = accountNumber.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').trim();
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
    final walletRef = _firestore.collection('users').doc(userId).collection('wallets').doc(walletId);
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
      paymentCode: (d['paymentCode'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      emvQrPayload: (d['emvQrPayload'] as String?) ?? '',
      status: status,
      matchedTransactionId: d['matchedTransactionId'] as String?,
      createdAt: cTs is Timestamp ? cTs.toDate() : DateTime.now(),
      paidAt: pTs is Timestamp ? pTs.toDate() : null,
    );
  }

  Stream<List<PaymentOrderEntity>> watchPaymentOrders(String userId) {
    return _paymentOrdersCol(userId).snapshots().map((snap) {
      final list = snap.docs.map((d) => _mapPaymentOrder(d.id, d.data())).toList()
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
    final cleanAcc = accountNumber.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').trim();
    if (cleanAcc.length < 6) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Vui lòng liên kết số tài khoản ngân hàng trước khi tạo mã QR.',
      );
    }
    final now = DateTime.now();
    final paymentCode = VietQrEmvBuilder.generatePaymentCode(prefix: 'LO');
    final cleanDesc = description.trim().isEmpty ? 'Thu tien' : description.trim();
    final memoWithCode = '$paymentCode ${VietQrEmvBuilder.toBankSafeAscii(cleanDesc, maxLength: 28)}'.trim();
    final emvQr = VietQrEmvBuilder.buildNapas247Payload(
      bankBin: bankBin,
      accountNumber: cleanAcc,
      amountVnd: amountMinor,
      memo: memoWithCode,
    );
    final orderId = 'ord_${paymentCode.toLowerCase()}_${now.millisecondsSinceEpoch}';
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
    // Step 1: Hard OTP / secret filter BEFORE touching any database or log!
    if (OtpRedactor.containsOtpOrSecret('$title $body')) {
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
    final syncObservedBalance = (consentData['syncObservedBalance'] as bool?) ?? true;
    final allowedPackages = (consentData['allowedPackages'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => e.toString())
        .toSet();

    if (!enabled || !allowedPackages.contains(packageName)) {
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
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.blockedOtpOrSecret,
        message: 'Đã chặn thông báo chứa mã xác thực.',
      );
    }
    final signal = parsed.signal;
    if (signal == null) {
      return const IngestionOutcome(
        kind: IngestionOutcomeKind.ignoredPackageOrFormat,
        message: 'Thông báo không phải biến động số dư.',
      );
    }

    // Step 4: Smart Linked Bank Account -> Wallet Routing (matches accountTail or bankCode)
    var targetWalletId = defaultWalletId;
    final bankAccSnap = await _bankAccountsCol(userId).get();
    if (bankAccSnap.docs.isNotEmpty) {
      final accounts = bankAccSnap.docs.map((d) => _mapBankAccount(d.id, d.data())).toList();
      LinkedBankAccountEntity? routed;
      if (signal.accountTail != null && signal.accountTail!.isNotEmpty) {
        routed = accounts
            .where((a) => a.accountTail.endsWith(signal.accountTail!))
            .firstOrNull;
      }
      routed ??= accounts.where((a) => a.bankCode == signal.bankCode).firstOrNull;
      if (routed != null && routed.walletId.isNotEmpty) {
        targetWalletId = routed.walletId;
      }
    }

    // Step 5: Check if incoming transfer matches a pending Dynamic VietQR Payment Order (`LO...`)
    PaymentOrderEntity? matchedOrder;
    if (signal.direction == 'credit') {
      final upperCombined = '$title $body'.toUpperCase();
      final pendingOrdersSnap = await _paymentOrdersCol(userId)
          .where('status', isEqualTo: PaymentOrderStatus.pending.name)
          .get();
      for (final doc in pendingOrdersSnap.docs) {
        final order = _mapPaymentOrder(doc.id, doc.data());
        final codeUpper = order.paymentCode.toUpperCase();
        if (codeUpper.isNotEmpty &&
            (signal.matchedPaymentCode?.toUpperCase() == codeUpper ||
                upperCombined.contains(codeUpper))) {
          matchedOrder = order;
          targetWalletId = order.walletId;
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
    final candidateWindowFps = BankNotificationParser.computeOverlappingSoftWindowFingerprints(
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
    final matchingExistingDocs = existingTxQuery.docs.where((d) {
      if (matchedOrder != null) {
        // Distinct QR payment codes are distinct payments even if same amount within 15 minutes
        return d.data()['crossSourceFingerprint'] == signal.crossSourceFingerprint;
      }
      final ts = d.data()['occurredAt'];
      if (ts is! Timestamp) return true;
      return ts.toDate().difference(signal.occurredAt).abs() <= const Duration(minutes: 15);
    }).toList();

    final shouldAutoCommitToLedger = autoConfirm || matchedOrder != null;
    var isDuplicate = false;
    final txId = matchedOrder != null
        ? 'qr_${signal.sourceEventKey.substring(0, 20)}'
        : 'prov_${signal.sourceEventKey.substring(0, 20)}';

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
      if (shouldAutoCommitToLedger) {
        final walletRef =
            _firestore.collection('users').doc(userId).collection('wallets').doc(targetWalletId);
        final wSnap = await tx.get(walletRef);
        if (wSnap.exists) {
          final curBal = (wSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
          final delta = signal.direction == 'credit' ? signal.amountMinor : -signal.amountMinor;
          // If bank notification carries exact post-tx `SD:` balance and syncObservedBalance is enabled, sync exact balance!
          newWalletBal = (syncObservedBalance && signal.observedBalanceMinor != null)
              ? signal.observedBalanceMinor!
              : (curBal + delta);
          resolvedWalletName = (wSnap.data()?['name'] as String?) ?? 'Ngân hàng';
          tx.update(walletRef, {
            'balanceMinor': newWalletBal,
            if (syncObservedBalance && signal.observedBalanceMinor != null)
              'isEstimatedBalance': false,
            'updatedAt': Timestamp.fromDate(now),
          });
        }
      }

      if (matchedOrder != null) {
        tx.update(_paymentOrdersCol(userId).doc(matchedOrder.id), {
          'status': PaymentOrderStatus.paid.name,
          'receivedAmountMinor': signal.amountMinor,
          'matchedTransactionId': txId,
          'paidAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        });
      }

      tx.set(eventRef, {
        'eventKey': signal.sourceEventKey,
        'source': 'android_notification',
        'status': matchedOrder != null
            ? 'qr_order_reconciled'
            : (autoConfirm ? 'auto_confirmed' : 'provisional_created'),
        'linkedTransactionId': txId,
        if (matchedOrder != null) 'matchedOrderId': matchedOrder.id,
        'receivedAt': Timestamp.fromDate(now),
      });

      tx.set(
        _firestore.collection('users').doc(userId).collection('transactions').doc(txId),
        {
          'id': txId,
          'ownerId': userId,
          'walletId': targetWalletId,
          if (resolvedWalletName != null) 'walletName': resolvedWalletName,
          if (newWalletBal != null) 'balanceAfterMinor': newWalletBal,
          'categoryName': matchedOrder != null ? 'Thu tiền QR' : signal.categorySuggestion,
          'kind': signal.direction == 'credit' ? 'income' : 'expense',
          'direction': signal.direction,
          'amountMinor': signal.amountMinor,
          'currencyCode': 'VND',
          'merchant': matchedOrder != null
              ? '${matchedOrder.description} (${matchedOrder.paymentCode})'
              : '${signal.bankCode}: ${signal.merchant}',
          if (matchedOrder != null) 'note': 'Tự động đối soát mã QR ${matchedOrder.paymentCode}',
          'occurredAt': Timestamp.fromDate(signal.occurredAt),
          'monthKey': monthKey,
          'sourceKind': 'androidNotification',
          'verification': matchedOrder != null
              ? 'verified'
              : (autoConfirm ? 'userConfirmed' : 'provisional'),
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
        message: 'Giao dịch trùng lặp đã được bỏ qua.',
      );
    }

    // Step 6: Auto-settle Family / Group Split Debt if incoming memo carries `LIFEOS SPLIT...`!
    if (signal.direction == 'credit' &&
        signal.matchedPaymentCode != null &&
        signal.matchedPaymentCode!.startsWith('LIFEOS SPLIT')) {
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        final activeFamId = (userDoc.data()?['activeFamilyId'] as String?)?.trim();
        final receiverName = (userDoc.data()?['fullName'] as String?) ?? 'Thành viên';
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

    if (matchedOrder != null) {
      return IngestionOutcome(
        kind: IngestionOutcomeKind.autoReconciledOrder,
        transactionId: txId,
        matchedOrderId: matchedOrder.id,
        matchedPaymentCode: matchedOrder.paymentCode,
        message:
            'Đã nhận ${VndAmount.format(signal.amountMinor)} · Tự động gạch nợ mã ${matchedOrder.paymentCode}!',
      );
    }

    return IngestionOutcome(
      kind: IngestionOutcomeKind.createdProvisional,
      transactionId: txId,
      message: autoConfirm
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
          ? 'Giao dịch trùng lặp đã bỏ qua.'
          : 'Đã xác nhận giao dịch và cập nhật số dư ví.',
    );
  }

  Future<String> exportPersonalDataJson(String userId) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final wallets = await _firestore.collection('users').doc(userId).collection('wallets').get();
    final bankAccounts = await _bankAccountsCol(userId).get();
    final paymentOrders = await _paymentOrdersCol(userId).limit(100).get();
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
      'profile': sanitizeMap(userDoc.data()),
      'wallets': wallets.docs.map((d) => sanitizeMap(d.data())).toList(),
      'bankAccounts': bankAccounts.docs.map((d) => sanitizeMap(d.data())).toList(),
      'paymentOrders': paymentOrders.docs.map((d) => sanitizeMap(d.data())).toList(),
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
      if (i == 0 && RegExp(r'(date|ngay|amount|so_tien|description)', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      if (OtpRedactor.containsOtpOrSecret(line)) {
        continue;
      }

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
    await _bridge.syncConsentConfig(
      enabled: false,
      allowedPackages: const [],
      voiceSoundboxEnabled: false,
    );
    await NativeSecureVaultBridge.instance.clearAllSecrets();
    await NativeAlarmSchedulerBridge.instance.clearAllAlarms();

    final userDocRef = _firestore.collection('users').doc(userId);
    await userDocRef.set(
      {
        'id': userId,
        'deletionInProgress': true,
        'deletionStartedAt': Timestamp.fromDate(DateTime.now()),
      },
      SetOptions(merge: true),
    );

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

    const allPersonalSubcollections = [
      'wallets',
      'bank_accounts',
      'payment_orders',
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
  Stream<Result<List<LinkedBankAccountEntity>>> watchLinkedBankAccounts(String userId) {
    return _remoteDataSource
        .watchLinkedBankAccounts(userId)
        .map<Result<List<LinkedBankAccountEntity>>>((list) => Success(list))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (Object e, StackTrace _, EventSink<Result<List<LinkedBankAccountEntity>>> sink) {
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
      await _remoteDataSource.deleteLinkedBankAccount(userId: userId, accountId: accountId);
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
                (Object e, StackTrace _, EventSink<Result<List<PaymentOrderEntity>>> sink) {
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
