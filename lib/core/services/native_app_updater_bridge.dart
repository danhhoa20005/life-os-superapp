import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class InstalledAppMeta {
  final String versionName;
  final int buildNumber;
  final String packageName;
  final String abi;

  const InstalledAppMeta({
    required this.versionName,
    required this.buildNumber,
    required this.packageName,
    required this.abi,
  });

  String get displayVersion => '$versionName+$buildNumber';
}

class NativeAppUpdaterBridge {
  static const MethodChannel _channel = MethodChannel('vn.lifeos.app/app_updater');

  final InstalledAppMeta? fixedInstalledMeta;

  const NativeAppUpdaterBridge({this.fixedInstalledMeta});

  static const String compileTimeVersion = String.fromEnvironment(
    'APP_VERSION_NAME',
    defaultValue: '1.0.0',
  );
  static const int compileTimeBuildNumber = int.fromEnvironment(
    'APP_BUILD_NUMBER',
    defaultValue: 1,
  );

  Future<InstalledAppMeta> getInstalledAppVersion() async {
    if (fixedInstalledMeta != null) {
      return fixedInstalledMeta!;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const InstalledAppMeta(
        versionName: compileTimeVersion,
        buildNumber: compileTimeBuildNumber,
        packageName: 'vn.lifeos.app.life_os',
        abi: 'web_or_desktop',
      );
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getInstalledAppVersion');
      if (raw == null) {
        return const InstalledAppMeta(
          versionName: compileTimeVersion,
          buildNumber: compileTimeBuildNumber,
          packageName: 'vn.lifeos.app.life_os',
          abi: 'android',
        );
      }
      return InstalledAppMeta(
        versionName: (raw['versionName'] as String?) ?? compileTimeVersion,
        buildNumber: (raw['buildNumber'] as int?) ?? compileTimeBuildNumber,
        packageName: (raw['packageName'] as String?) ?? 'vn.lifeos.app.life_os',
        abi: (raw['abi'] as String?) ?? 'android',
      );
    } catch (_) {
      return const InstalledAppMeta(
        versionName: compileTimeVersion,
        buildNumber: compileTimeBuildNumber,
        packageName: 'vn.lifeos.app.life_os',
        abi: 'android',
      );
    }
  }

  Future<String> getUpdateCacheDir() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final path = await _channel.invokeMethod<String>('getUpdateCacheDir');
        if (path != null && path.isNotEmpty) return path;
      } catch (_) {}
    }
    final fallback = Directory('${Directory.systemTemp.path}/life_os_ota');
    if (!fallback.existsSync()) {
      fallback.createSync(recursive: true);
    }
    return fallback.path;
  }

  Future<String> installApk(String filePath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'UNSUPPORTED_PLATFORM';
    }
    final status = await _channel.invokeMethod<String>(
      'installApk',
      <String, dynamic>{'filePath': filePath},
    );
    return status ?? 'UNKNOWN';
  }

  Future<bool> openExternalUrl(String url) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final ok = await _channel.invokeMethod<bool>(
        'openExternalUrl',
        <String, dynamic>{'url': url},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
