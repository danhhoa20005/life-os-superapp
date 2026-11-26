import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../error/app_exception.dart';

enum AppSignatureVerificationStatus {
  match,
  mismatch,
  unreadable;

  static AppSignatureVerificationStatus fromWire(String? raw) {
    return switch (raw?.trim().toUpperCase()) {
      'MATCH' => AppSignatureVerificationStatus.match,
      'MISMATCH' => AppSignatureVerificationStatus.mismatch,
      _ => AppSignatureVerificationStatus.unreadable,
    };
  }
}

class ApkSignatureVerificationOutcome {
  final AppSignatureVerificationStatus status;
  final String? errorCode;
  final String? reasonVi;

  const ApkSignatureVerificationOutcome({
    required this.status,
    this.errorCode,
    this.reasonVi,
  });

  bool get isMatch => status == AppSignatureVerificationStatus.match;
}

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
  @visibleForTesting
  final bool? forceAndroidPlatformForTest;

  const NativeAppUpdaterBridge({
    this.fixedInstalledMeta,
    this.fixedDistributionFlavor,
    this.fixedGitHubOtaEnabled,
    this.forceAndroidPlatformForTest,
  });

  bool get _isAndroidRuntime =>
      !kIsWeb && (forceAndroidPlatformForTest ?? Platform.isAndroid);

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

  Future<ApkSignatureVerificationOutcome> verifyApkSignature(
    String filePath,
  ) async {
    if (!await isGitHubOtaEnabled()) {
      return const ApkSignatureVerificationOutcome(
        status: AppSignatureVerificationStatus.mismatch,
        errorCode: 'OTA_DISABLED_PLAY_FLAVOR',
        reasonVi:
            'Phiên bản Google Play không hỗ trợ tự tải và cài đặt tệp APK trong ứng dụng.',
      );
    }
    if (!_isAndroidRuntime) {
      return const ApkSignatureVerificationOutcome(
        status: AppSignatureVerificationStatus.unreadable,
        errorCode: 'UNSUPPORTED_PLATFORM',
        reasonVi: 'Nền tảng hiện tại không hỗ trợ xác minh gói APK Android.',
      );
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'verifyApkSignature',
        <String, dynamic>{'filePath': filePath},
      );
      if (raw == null) {
        return const ApkSignatureVerificationOutcome(
          status: AppSignatureVerificationStatus.unreadable,
          errorCode: 'CERT_UNREADABLE',
          reasonVi:
              'Không thể đọc phản hồi xác minh chữ ký số từ hệ thống Android.',
        );
      }
      final sigRaw = (raw['signatureStatus'] ?? raw['status'])?.toString();
      final status = AppSignatureVerificationStatus.fromWire(sigRaw);
      return ApkSignatureVerificationOutcome(
        status: status,
        errorCode: raw['errorCode']?.toString(),
        reasonVi: raw['reason']?.toString(),
      );
    } on PlatformException catch (e) {
      return ApkSignatureVerificationOutcome(
        status: e.code == 'CERT_MISMATCH'
            ? AppSignatureVerificationStatus.mismatch
            : AppSignatureVerificationStatus.unreadable,
        errorCode: e.code,
        reasonVi: e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'Không thể xác minh chữ ký số của tệp APK.',
      );
    }
  }

  Future<String> installApk(String filePath) async {
    if (!await isGitHubOtaEnabled()) {
      throw const AppException(
        code: 'OTA_DISABLED_PLAY_FLAVOR',
        message:
            'Phiên bản Google Play không hỗ trợ tự tải và cài đặt tệp APK trong ứng dụng.',
      );
    }
    if (!_isAndroidRuntime) {
      return 'UNSUPPORTED_PLATFORM';
    }
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'installApk',
        <String, dynamic>{'filePath': filePath},
      );
      if (raw is Map) {
        final sigStatusRaw = (raw['signatureStatus'] ?? raw['status'])
            ?.toString()
            .toUpperCase();
        if (sigStatusRaw == 'MISMATCH' || sigStatusRaw == 'UNREADABLE') {
          final reason = raw['reason']?.toString().trim();
          throw AppException(
            code: sigStatusRaw == 'UNREADABLE'
                ? 'OTA_CERT_UNREADABLE'
                : 'OTA_CERT_MISMATCH',
            message: (reason != null && reason.isNotEmpty)
                ? reason
                : 'Không thể xác minh chữ ký số của gói APK cập nhật (APP-03).',
          );
        }
        return raw['status']?.toString() ?? 'UNKNOWN';
      }
      return raw?.toString() ?? 'UNKNOWN';
    } on PlatformException catch (e) {
      final details = e.details;
      final sigStatus = details is Map
          ? (details['signatureStatus'] ?? details['status'])
                ?.toString()
                .toUpperCase()
          : null;
      final detailReason = details is Map
          ? details['reason']?.toString().trim()
          : null;
      final reason = (e.message?.trim().isNotEmpty == true)
          ? e.message!.trim()
          : (detailReason?.isNotEmpty == true
                ? detailReason!
                : 'Không thể xác minh chữ ký số hoặc cài đặt gói APK (${e.code}).');
      final mappedCode = switch (e.code) {
        'CERT_MISMATCH' => 'OTA_CERT_MISMATCH',
        'CERT_UNREADABLE' => 'OTA_CERT_UNREADABLE',
        _ when sigStatus == 'UNREADABLE' => 'OTA_CERT_UNREADABLE',
        _ when sigStatus == 'MISMATCH' => 'OTA_CERT_MISMATCH',
        _ => e.code.isNotEmpty ? e.code : 'OTA_INSTALL_FAILED',
      };
      throw AppException(code: mappedCode, message: reason);
    }
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
