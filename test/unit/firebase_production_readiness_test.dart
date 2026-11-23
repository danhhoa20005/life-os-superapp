import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app/config/firebase_config.dart';
import 'package:life_os/firebase_options.dart';

void main() {
  group('Firebase Production Readiness Verification (life-os-vn-2026)', () {
    test('android/app/google-services.json has populated Android & Web OAuth 2.0 clients', () {
      final raw = File('android/app/google-services.json').readAsStringSync();
      final json = jsonDecode(raw) as Map<String, dynamic>;

      expect(
        (json['project_info'] as Map<String, dynamic>)['project_id'],
        'life-os-vn-2026',
      );

      final client = (json['client'] as List<dynamic>).first as Map<String, dynamic>;
      final oauthClients = client['oauth_client'] as List<dynamic>;
      expect(oauthClients.length, greaterThanOrEqualTo(2));

      final androidOauth = oauthClients
          .cast<Map<String, dynamic>>()
          .firstWhere((c) => c['client_type'] == 1);
      final webOauth = oauthClients
          .cast<Map<String, dynamic>>()
          .firstWhere((c) => c['client_type'] == 3);

      expect(
        (androidOauth['android_info'] as Map<String, dynamic>)['package_name'],
        'vn.lifeos.app.life_os',
      );
      expect(
        webOauth['client_id'],
        FirebaseConfig.defaultGoogleWebClientId,
      );

      final gradleFile = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradleFile, contains('id("com.google.gms.google-services")'));
    });

    test('ios/Runner/GoogleService-Info.plist & Info.plist have Google Sign-In OAuth schemes', () {
      final gsPlist = File('ios/Runner/GoogleService-Info.plist').readAsStringSync();
      final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(gsPlist, contains(FirebaseConfig.defaultGoogleIosClientId));
      expect(gsPlist, contains('<key>REVERSED_CLIENT_ID</key>'));
      expect(infoPlist, contains('<key>GIDClientID</key>'));
      expect(infoPlist, contains('<key>GIDServerClientID</key>'));
      expect(
        infoPlist,
        contains('com.googleusercontent.apps.913180533540-3drd28gcsvh57175vg1d5h2qkhan5qg3'),
      );
    });

    test('DefaultFirebaseOptions & firestore.indexes.json are aligned with Cloud project', () {
      expect(DefaultFirebaseOptions.android.projectId, 'life-os-vn-2026');
      expect(DefaultFirebaseOptions.android.androidClientId, isNotEmpty);
      expect(DefaultFirebaseOptions.ios.iosClientId, FirebaseConfig.defaultGoogleIosClientId);

      final indexesJson =
          jsonDecode(File('firestore.indexes.json').readAsStringSync()) as Map<String, dynamic>;
      final indexes = indexesJson['indexes'] as List<dynamic>;
      expect(indexes.length, 13);
    });
  });
}
