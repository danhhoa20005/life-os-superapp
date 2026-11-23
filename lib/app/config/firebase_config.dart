import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../firebase_options.dart';

abstract final class FirebaseConfig {
  static const bool useEmulatorFlag = bool.fromEnvironment(
    'USE_FIREBASE_EMULATOR',
    defaultValue: false,
  );

  static const String emulatorHostOverride = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '',
  );

  /// Official Web OAuth 2.0 Client ID (`client_type: 3`) provisioned by Firebase Authentication
  /// for `life-os-vn-2026`. Used as `serverClientId` on Android/iOS so Play Services Credential
  /// Manager returns a verified `idToken` for both Firebase Auth & Google Calendar API v3.
  static const String defaultGoogleWebClientId =
      '913180533540-0guqo9do0n0varqhfstc7hae2g84c6dt.apps.googleusercontent.com';

  /// Official iOS OAuth 2.0 Client ID (`client_type: 2`) from `GoogleService-Info.plist`.
  static const String defaultGoogleIosClientId =
      '913180533540-3drd28gcsvh57175vg1d5h2qkhan5qg3.apps.googleusercontent.com';

  static const String _envGoogleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: defaultGoogleWebClientId,
  );

  static String get googleWebClientId => _envGoogleWebClientId.isNotEmpty
      ? _envGoogleWebClientId
      : defaultGoogleWebClientId;

  static Future<void>? _googleSignInInitFuture;

  static bool get isGoogleSignInInitialized => _googleSignInInitFuture != null;

  /// Ensures `GoogleSignIn.instance.initialize` runs at most once per app lifecycle
  /// with unified `serverClientId` (and `clientId` on iOS) across Auth and Calendar.
  static Future<void> ensureGoogleSignInInitialized() {
    return _googleSignInInitFuture ??= GoogleSignIn.instance.initialize(
      clientId: (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
          ? defaultGoogleIosClientId
          : null,
      serverClientId: googleWebClientId,
    );
  }

  static bool _runtimeEmulatorFallbackActive = false;

  static bool get shouldUseEmulator =>
      useEmulatorFlag ||
      _runtimeEmulatorFallbackActive ||
      DefaultFirebaseOptions.currentPlatform.projectId.startsWith('demo-');

  static bool get isCloudProduction => !shouldUseEmulator;

  static String get resolvedEmulatorHost {
    if (emulatorHostOverride.isNotEmpty) return emulatorHostOverride;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }
    return '127.0.0.1';
  }

  /// Probes whether real Cloud Firebase Authentication (`life-os-vn-2026`) is active.
  /// Returns `true` when Cloud Auth responds normally; returns `false` ONLY if the
  /// Spark project still awaits the 1-time Console "Get started" click (`CONFIGURATION_NOT_FOUND`).
  static Future<bool> _isCloudAuthProvisioned(String apiKey) async {
    if (apiKey.isEmpty) return true;
    try {
      final res = await http
          .post(
            Uri.parse(
              'https://identitytoolkit.googleapis.com/v1/accounts:createAuthUri?key=$apiKey',
            ),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(const {
              'identifier': 'probe@lifeos.vn',
              'continueUri': 'http://localhost',
            }),
          )
          .timeout(const Duration(milliseconds: 1100));
      if (res.statusCode == 400 &&
          res.body.contains('CONFIGURATION_NOT_FOUND')) {
        return false;
      }
      return true;
    } catch (_) {
      // Offline or transient network: keep real Cloud Firebase persistence active!
      return true;
    }
  }

  /// Checks if a local dev/QA Firebase Emulator bridge (`adb reverse` `127.0.0.1:9199`
  /// or Android AVD `10.0.2.2:9199`) is reachable on the device.
  static Future<String?> _detectReachableLocalEmulatorHost() async {
    if (kIsWeb) return null;
    final candidates = <String>[
      if (emulatorHostOverride.isNotEmpty) emulatorHostOverride,
      '127.0.0.1',
      if (defaultTargetPlatform == TargetPlatform.android) '10.0.2.2',
    ];
    for (final host in candidates) {
      try {
        final sock = await Socket.connect(
          host,
          9199,
          timeout: const Duration(milliseconds: 350),
        );
        sock.destroy();
        return host;
      } catch (_) {}
    }
    return null;
  }

  static Future<void> initialize() async {
    final options = DefaultFirebaseOptions.currentPlatform;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }

    if (useEmulatorFlag || options.projectId.startsWith('demo-')) {
      final host = resolvedEmulatorHost;
      await FirebaseAuth.instance.useAuthEmulator(host, 9199);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8188);
    } else {
      final cloudReady = await _isCloudAuthProvisioned(options.apiKey);
      if (!cloudReady) {
        final bridgeHost = await _detectReachableLocalEmulatorHost();
        if (bridgeHost != null) {
          _runtimeEmulatorFallbackActive = true;
          await FirebaseAuth.instance.useAuthEmulator(bridgeHost, 9199);
          FirebaseFirestore.instance.useFirestoreEmulator(bridgeHost, 8188);
        }
      }
    }

    // Deliver password-reset & email-verification emails in Vietnamese
    try {
      await FirebaseAuth.instance.setLanguageCode('vi');
    } catch (_) {}

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }
}
