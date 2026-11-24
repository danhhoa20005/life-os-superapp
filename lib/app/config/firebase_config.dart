import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  /// F20 / OPS-01: Production builds NEVER probe local ports or silently fall back to Firebase Emulator.
  /// Emulator is used ONLY when explicitly requested in non-release builds (`--dart-define=USE_FIREBASE_EMULATOR=true`
  /// or explicit `demo-*` test project).
  static bool canUseEmulatorFor({
    required bool isReleaseBuild,
    required bool explicitEmulatorFlag,
    required String projectId,
  }) {
    if (isReleaseBuild) return false;
    return explicitEmulatorFlag || projectId.startsWith('demo-');
  }

  static bool get shouldUseEmulator => canUseEmulatorFor(
    isReleaseBuild: kReleaseMode,
    explicitEmulatorFlag: useEmulatorFlag,
    projectId: DefaultFirebaseOptions.currentPlatform.projectId,
  );

  static bool get isCloudProduction => !shouldUseEmulator;

  static String get resolvedEmulatorHost {
    if (emulatorHostOverride.isNotEmpty) return emulatorHostOverride;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }
    return '127.0.0.1';
  }

  static Future<void> initialize() async {
    final options = DefaultFirebaseOptions.currentPlatform;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }

    if (shouldUseEmulator) {
      final host = resolvedEmulatorHost;
      await FirebaseAuth.instance.useAuthEmulator(host, 9199);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8188);
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
