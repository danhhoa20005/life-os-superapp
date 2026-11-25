import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../error/app_exception.dart';

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
  static const MethodChannel _channel = MethodChannel(
    'vn.lifeos.app/app_updater',
  );

  final InstalledAppMeta? fixedInstalledMeta;
  final String? fixedDistributionFlavor;
  final bool? fixedGitHubOtaEnabled;

  const NativeAppUpdaterBridge({
    this.fixedInstalledMeta,
    this.fixedDistributionFlavor,
    this.fixedGitHubOtaEnabled,
  });

  static const String compileTimeVersion = String.fromEnvironment(
    'APP_VERSION_NAME',
    defaultValue: '3.16.0',
  );
  static const int compileTimeBuildNumber = int.fromEnvironment(
    'APP_BUILD_NUMBER',
    defaultValue: 31,
  );
  static const String compileTimeDistributionFlavor = String.fromEnvironment(
    'DISTRIBUTION_FLAVOR',
    defaultValue: 'github',
  );
  static const bool compileTimeGitHubOtaEnabled = bool.fromEnvironment(
    'ENABLE_GITHUB_OTA',
    defaultValue: true,
  );

  Future<String> getDistributionFlavor() async {
    if (fixedDistributionFlavor != null) {
      return fixedDistributionFlavor!;
    }
    if (kIsWeb || !Platform.isAndroid) {
      return compileTimeDistributionFlavor;
    }
    try {
      final flavor = await _channel.invokeMethod<String>(
        'getDistributionFlavor',
      );
      if (flavor == 'github' || flavor == 'play') {
        return flavor!;
      }
    } catch (_) {}
    return compileTimeDistributionFlavor;
  }

  Future<bool> isGitHubOtaEnabled() async {
    if (fixedGitHubOtaEnabled != null) {
      return fixedGitHubOtaEnabled!;
    }
    if (fixedDistributionFlavor != null) {
      return fixedDistributionFlavor == 'github';
    }
    if (kIsWeb || !Platform.isAndroid) {
      return compileTimeGitHubOtaEnabled;
    }
    try {
      final enabled = await _channel.invokeMethod<bool>('isGitHubOtaEnabled');
      if (enabled != null) {
        return enabled;
      }
    } catch (_) {}
    return compileTimeGitHubOtaEnabled;
  }

  Future<InstalledAppMeta> getInstalledAppVersion() async {
    if (fixedInstalledMeta != null) {
      return fixedInstalledMeta!;
    }
    if (kIsWeb || !Platform.isAndroid) {
      return const InstalledAppMeta(
        versionName: compileTimeVersion,
        buildNumber: compileTimeBuildNumber,
        packageName: 'vn.lifeos.app.life_os',
        abi: 'web_or_desktop',
      );
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getInstalledAppVersion',
      );
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
    if (!await isGitHubOtaEnabled()) {
      throw const AppException(
        code: 'OTA_DISABLED_PLAY_FLAVOR',
        message:
            'Phiên bản Google Play không hỗ trợ tự tải và cài đặt tệp APK trong ứng dụng.',
      );
    }
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
    if (!await isGitHubOtaEnabled()) {
      throw const AppException(
        code: 'OTA_DISABLED_PLAY_FLAVOR',
        message:
            'Phiên bản Google Play không hỗ trợ tự tải và cài đặt tệp APK trong ứng dụng.',
      );
    }
    if (kIsWeb || !Platform.isAndroid) {
      return 'UNSUPPORTED_PLATFORM';
    }
    final status = await _channel.invokeMethod<String>(
      'installApk',
      <String, dynamic>{'filePath': filePath},
    );
    return status ?? 'UNKNOWN';
  }

  Future<bool> openExternalUrl(String url) async {
    if (kIsWeb || !Platform.isAndroid) {
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

  Future<String?> shareTextFile({
    required String fileName,
    required String content,
    String mimeType = 'text/csv',
    String title = 'Xuất Sao kê Sổ cái Life OS',
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final path = await _channel
            .invokeMethod<String>('shareTextFile', <String, dynamic>{
              'fileName': fileName,
              'content': content,
              'mimeType': mimeType,
              'title': title,
            });
        if (path != null && path.isNotEmpty) return path;
      } catch (_) {}
    }
    await Clipboard.setData(ClipboardData(text: content));
    return null;
  }
}
