import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

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

  static bool get shouldUseEmulator =>
      useEmulatorFlag || DefaultFirebaseOptions.currentPlatform.projectId.startsWith('demo-');

  static String get resolvedEmulatorHost {
    if (emulatorHostOverride.isNotEmpty) return emulatorHostOverride;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }
    return '127.0.0.1';
  }

  static Future<void> initialize() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    if (shouldUseEmulator) {
      final host = resolvedEmulatorHost;
      await FirebaseAuth.instance.useAuthEmulator(host, 9199);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8188);
    }

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  }
}
