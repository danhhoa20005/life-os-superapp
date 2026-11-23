import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Top-level Firebase Cloud Messaging background handler (required by FlutterFire when app is backgrounded/terminated).
/// Note: Server-side Cloud Functions (`sepayWebhook` -> `processSePayInboxWorker`) ALREADY persist
/// the canonical transaction in Firestore independently of the device!
@pragma('vm:entry-point')
Future<void> lifeOsFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  // Data is already persisted durably on server; OS displays notification payload automatically.
}

class IncomingBankingPushPayload {
  final String notificationId;
  final String transactionId;
  final String walletId;
  final String connectionId;
  final String direction;
  final String verificationStatus;
  final String title;
  final String body;
  final bool openedFromSystemTray;

  const IncomingBankingPushPayload({
    required this.notificationId,
    required this.transactionId,
    required this.walletId,
    required this.connectionId,
    required this.direction,
    required this.verificationStatus,
    required this.title,
    required this.body,
    required this.openedFromSystemTray,
  });
}

abstract interface class FcmPlatformDriver {
  Future<bool> requestPushPermission();
  Future<void> registerDevice();
  Future<void> unregisterDevice();
  Stream<String> get onRegistered;
  Stream<IncomingBankingPushPayload> get onForegroundMessage;
  Stream<IncomingBankingPushPayload> get onMessageOpenedApp;
  Future<IncomingBankingPushPayload?> getInitialTerminatedMessage();
}

class FirebaseFcmPlatformDriver implements FcmPlatformDriver {
  const FirebaseFcmPlatformDriver();

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  IncomingBankingPushPayload? _mapRemoteMessage(
    RemoteMessage? msg, {
    required bool openedFromSystemTray,
  }) {
    if (msg == null) return null;
    final d = msg.data;
    if (d['type'] != 'bank_transaction' &&
        (d['transactionId'] ?? '').toString().isEmpty) {
      return null;
    }
    final txId = (d['transactionId'] ?? '').toString();
    final notifId = (d['notificationId'] ?? msg.messageId ?? 'push_$txId')
        .toString();
    return IncomingBankingPushPayload(
      notificationId: notifId,
      transactionId: txId,
      walletId: (d['walletId'] ?? '').toString(),
      connectionId: (d['connectionId'] ?? '').toString(),
      direction: (d['direction'] ?? 'credit').toString(),
      verificationStatus: (d['verificationStatus'] ?? 'VERIFIED').toString(),
      title: msg.notification?.title ?? 'Life OS — Biến động ngân hàng',
      body: msg.notification?.body ?? '',
      openedFromSystemTray: openedFromSystemTray,
    );
  }

  @override
  Future<bool> requestPushPermission() async {
    if (!_supported) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> registerDevice() async {
    if (!_supported) return;
    try {
      await FirebaseMessaging.instance.register();
    } catch (_) {}
  }

  @override
  Future<void> unregisterDevice() async {
    if (!_supported) return;
    try {
      await FirebaseMessaging.instance.unregister();
    } catch (_) {}
  }

  @override
  Stream<String> get onRegistered {
    if (!_supported) return const Stream<String>.empty();
    try {
      return FirebaseMessaging.instance.onRegistered;
    } catch (_) {
      return const Stream<String>.empty();
    }
  }

  @override
  Stream<IncomingBankingPushPayload> get onForegroundMessage {
    if (!_supported) return const Stream<IncomingBankingPushPayload>.empty();
    try {
      return FirebaseMessaging.onMessage
          .map((m) => _mapRemoteMessage(m, openedFromSystemTray: false))
          .where((p) => p != null)
          .cast<IncomingBankingPushPayload>();
    } catch (_) {
      return const Stream<IncomingBankingPushPayload>.empty();
    }
  }

  @override
  Stream<IncomingBankingPushPayload> get onMessageOpenedApp {
    if (!_supported) return const Stream<IncomingBankingPushPayload>.empty();
    try {
      return FirebaseMessaging.onMessageOpenedApp
          .map((m) => _mapRemoteMessage(m, openedFromSystemTray: true))
          .where((p) => p != null)
          .cast<IncomingBankingPushPayload>();
    } catch (_) {
      return const Stream<IncomingBankingPushPayload>.empty();
    }
  }

  @override
  Future<IncomingBankingPushPayload?> getInitialTerminatedMessage() async {
    if (!_supported) return null;
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      return _mapRemoteMessage(initial, openedFromSystemTray: true);
    } catch (_) {
      return null;
    }
  }
}

/// Manages per-user FCM device registration lifecycle (`register` / `onRegistered` / `unregister`),
/// foreground banner deduplication (`T11`, `T18`), background/terminated deep-link navigation (`T12`, `T13`),
/// and strict logout cleanup (`T16`).
class FcmBankingMessagingService {
  final FirebaseFirestore _firestore;
  final FcmPlatformDriver _driver;

  String? _activeUserId;
  String? _activeDeviceId;
  StreamSubscription<String>? _registeredSub;
  StreamSubscription<IncomingBankingPushPayload>? _foregroundSub;
  StreamSubscription<IncomingBankingPushPayload>? _openedSub;

  final Set<String> _seenForegroundNotificationIds = <String>{};
  final StreamController<IncomingBankingPushPayload> _foregroundEventsCtrl =
      StreamController<IncomingBankingPushPayload>.broadcast();
  final StreamController<IncomingBankingPushPayload> _deepLinkEventsCtrl =
      StreamController<IncomingBankingPushPayload>.broadcast();

  IncomingBankingPushPayload? _pendingColdStartDeepLink;

  FcmBankingMessagingService({
    required FirebaseFirestore firestore,
    FcmPlatformDriver? driver,
  }) : _firestore = firestore,
       _driver = driver ?? const FirebaseFcmPlatformDriver();

  Stream<IncomingBankingPushPayload> get foregroundNotifications =>
      _foregroundEventsCtrl.stream;

  Stream<IncomingBankingPushPayload> get deepLinkRequests =>
      _deepLinkEventsCtrl.stream;

  IncomingBankingPushPayload? consumePendingColdStartDeepLink() {
    final pending = _pendingColdStartDeepLink;
    _pendingColdStartDeepLink = null;
    return pending;
  }

  static String computeDeterministicDeviceId(String token) {
    final digest = sha256.convert(token.codeUnits).toString().substring(0, 20);
    return 'dev_$digest';
  }

  /// Registers FCM listeners and device token strictly scoped to `userId`.
  /// If a previous user was active on this device, deactivates their registration first (T16).
  Future<bool> bindAuthenticatedUser(String userId) async {
    if (_activeUserId != null && _activeUserId != userId) {
      await unbindAndDeactivateOnLogout();
    }
    _activeUserId = userId;
    _seenForegroundNotificationIds.clear();

    final granted = await _driver.requestPushPermission();

    await _registeredSub?.cancel();
    _registeredSub = _driver.onRegistered.listen((newToken) {
      final uid = _activeUserId;
      if (uid != null && newToken.trim().isNotEmpty) {
        _upsertUserDeviceToken(
          userId: uid,
          token: newToken,
          pushEnabled: granted,
        );
      }
    });

    await _driver.registerDevice();

    await _foregroundSub?.cancel();
    _foregroundSub = _driver.onForegroundMessage.listen((payload) {
      if (_activeUserId != userId) return;
      if (_seenForegroundNotificationIds.contains(payload.notificationId)) {
        return;
      }
      _seenForegroundNotificationIds.add(payload.notificationId);
      _foregroundEventsCtrl.add(payload);
    });

    await _openedSub?.cancel();
    _openedSub = _driver.onMessageOpenedApp.listen((payload) {
      if (_activeUserId != userId) return;
      _deepLinkEventsCtrl.add(payload);
    });

    final coldStart = await _driver.getInitialTerminatedMessage();
    if (coldStart != null && _activeUserId == userId) {
      _pendingColdStartDeepLink = coldStart;
      _deepLinkEventsCtrl.add(coldStart);
    }

    return granted;
  }

  Future<void> _upsertUserDeviceToken({
    required String userId,
    required String token,
    required bool pushEnabled,
  }) async {
    final devId = computeDeterministicDeviceId(token);
    _activeDeviceId = devId;
    final platformName = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      _ => 'android',
    };
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(devId)
        .set({
          'deviceId': devId,
          'ownerId': userId,
          'fcmToken': token,
          'platform': platformName,
          'pushEnabled': pushEnabled,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        }, SetOptions(merge: true));
  }

  /// T16: Deactivates current device token & unregisters FCM immediately upon logout!
  Future<void> unbindAndDeactivateOnLogout() async {
    final prevUser = _activeUserId;
    final prevDev = _activeDeviceId;
    _activeUserId = null;
    _activeDeviceId = null;
    _pendingColdStartDeepLink = null;
    _seenForegroundNotificationIds.clear();

    await _registeredSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _registeredSub = null;
    _foregroundSub = null;
    _openedSub = null;

    await _driver.unregisterDevice();

    if (prevUser != null && prevDev != null) {
      try {
        await _firestore
            .collection('users')
            .doc(prevUser)
            .collection('devices')
            .doc(prevDev)
            .set({
              'deviceId': prevDev,
              'ownerId': prevUser,
              'pushEnabled': false,
              'loggedOutAt': Timestamp.fromDate(DateTime.now()),
            }, SetOptions(merge: true));
      } catch (_) {}
    }
  }
}
