import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
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

  static bool _runtimeEmulatorFallbackActive = false;

  static bool get shouldUseEmulator =>
      useEmulatorFlag ||
      _runtimeEmulatorFallbackActive ||
      DefaultFirebaseOptions.currentPlatform.projectId.startsWith('demo-');

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
      if (res.statusCode == 400 && res.body.contains('CONFIGURATION_NOT_FOUND')) {
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

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  }
}
