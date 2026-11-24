import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/error/app_exception.dart';
import '../../../../core/services/native_app_updater_bridge.dart';
import '../../domain/entities/app_update_entities.dart';

class AppUpdateRemoteDataSource {
  static const String githubOwner = 'danhhoa20005';
  static const String githubRepo = 'life-os-superapp';
  static const String defaultGithubReleasesUrl =
      'https://github.com/$githubOwner/$githubRepo/releases';
  static const String githubLatestApiUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  static const Set<String> trustedOtaHosts = <String>{
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
    'firebasestorage.googleapis.com',
  };

  static final RegExp _sha256HexRegex = RegExp(r'^[a-fA-F0-9]{64}$');
  static final RegExp _bodySha256Regex = RegExp(
    r'(?:sha[-_]?256\s*[:=]\s*|`|\b)([a-fA-F0-9]{64})\b',
    caseSensitive: false,
  );

  final FirebaseFirestore _firestore;
  final NativeAppUpdaterBridge _updaterBridge;
  final http.Client _httpClient;

  AppUpdateRemoteDataSource({
    required FirebaseFirestore firestore,
    required NativeAppUpdaterBridge updaterBridge,
    http.Client? httpClient,
  }) : _firestore = firestore,
       _updaterBridge = updaterBridge,
       _httpClient = httpClient ?? http.Client();

  static bool isTrustedDownloadUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return trustedOtaHosts.contains(host);
  }

  static String? normalizeSha256(String? raw) {
    if (raw == null) return null;
    var cleaned = raw.trim();
    if (cleaned.toLowerCase().startsWith('sha256:')) {
      cleaned = cleaned.substring(7).trim();
    }
    if (_sha256HexRegex.hasMatch(cleaned)) {
      return cleaned.toLowerCase();
    }
    return null;
  }

  static String? extractSha256FromReleaseNotes(String body) {
    final m = _bodySha256Regex.firstMatch(body);
    return normalizeSha256(m?.group(1));
  }

  Future<InstalledAppMeta> getInstalledVersion() =>
      _updaterBridge.getInstalledAppVersion();

  Future<AppReleaseManifest?> fetchLatestManifest() async {
    final results = await Future.wait<AppReleaseManifest?>([
      _fetchFromFirestore(),
      _fetchFromGithubReleases(),
    ]);

    AppReleaseManifest? best;
    for (final candidate in results) {
      if (candidate == null) continue;
      if (best == null) {
        best = candidate;
        continue;
      }
      if (candidate.semanticVersion.isNewerThan(best.semanticVersion)) {
        best = candidate;
      } else if (!best.semanticVersion.isNewerThan(candidate.semanticVersion) &&
          normalizeSha256(best.apkSha256) == null &&
          normalizeSha256(candidate.apkSha256) != null) {
        // Prefer the manifest carrying verified SHA-256 metadata for the same release version
        best = candidate;
      }
    }
    return best;
  }

  Future<AppReleaseManifest?> _fetchFromFirestore() async {
    try {
      final snap = await _firestore
          .collection('app_config')
          .doc('release_manifest')
          .get()
          .timeout(const Duration(seconds: 5));
      if (!snap.exists) return null;
      final d = snap.data();
      if (d == null) return null;

      final latestVersion = (d['latestVersion'] as String?)?.trim() ?? '';
      if (latestVersion.isEmpty) return null;

      final rawChangelog = d['changelog'];
      final changelog = rawChangelog is Iterable
          ? rawChangelog
                .map((e) => e.toString())
                .where((s) => s.isNotEmpty)
                .toList()
          : <String>['Cải thiện hiệu năng, bảo mật và trải nghiệm người dùng.'];

      final pubTs = d['publishedAt'];
      final publishedAt = pubTs is Timestamp
          ? pubTs.toDate()
          : DateTime.tryParse((d['publishedAt'] ?? '').toString()) ??
                DateTime.now();

      return AppReleaseManifest(
        latestVersion: latestVersion,
        latestBuildNumber: (d['latestBuildNumber'] as num?)?.toInt() ?? 0,
        minSupportedVersion: (d['minSupportedVersion'] as String?) ?? '1.0.0',
        releaseTitle:
            (d['releaseTitle'] as String?) ?? 'Life OS v$latestVersion',
        changelog: changelog,
        apkDownloadUrl: d['apkDownloadUrl'] as String?,
        htmlReleaseUrl:
            (d['htmlReleaseUrl'] as String?) ?? defaultGithubReleasesUrl,
        apkSizeBytes: (d['apkSizeBytes'] as num?)?.toInt(),
        apkSha256: normalizeSha256(d['apkSha256'] as String?),
        publishedAt: publishedAt,
        sourceName: 'Firebase Cloud',
      );
    } catch (_) {
      return null;
    }
  }

  Future<AppReleaseManifest?> _fetchFromGithubReleases() async {
    try {
      final response = await _httpClient
          .get(
            Uri.parse(githubLatestApiUrl),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'LifeOS-SuperApp-Updater',
            },
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      if (data['draft'] == true) return null;

      final tagName = (data['tag_name'] as String?)?.trim() ?? '';
      if (tagName.isEmpty) return null;
      final parsedSemVer = SemanticAppVersion.parse(tagName);

      String? apkUrl;
      int? apkSize;
      String? apkSha256;
      String? sidecarSha256Url;

      final assets = data['assets'];
      if (assets is Iterable) {
        for (final asset in assets) {
          if (asset is Map<String, dynamic>) {
            final name = (asset['name'] as String?)?.toLowerCase() ?? '';
            if (name.endsWith('.apk')) {
              apkUrl = asset['browser_download_url'] as String?;
              apkSize = (asset['size'] as num?)?.toInt();
              apkSha256 = normalizeSha256(asset['digest'] as String?);
            } else if (name.endsWith('.apk.sha256') || name.endsWith('.sha256')) {
              sidecarSha256Url = asset['browser_download_url'] as String?;
            }
          }
        }
      }

      final rawBody = (data['body'] as String?) ?? '';
      apkSha256 ??= extractSha256FromReleaseNotes(rawBody);

      if (apkSha256 == null &&
          sidecarSha256Url != null &&
          isTrustedDownloadUrl(sidecarSha256Url)) {
        try {
          final sidecarRes = await _httpClient
              .get(Uri.parse(sidecarSha256Url))
              .timeout(const Duration(seconds: 4));
          if (sidecarRes.statusCode == 200) {
            final firstToken = sidecarRes.body
                .trim()
                .split(RegExp(r'\s+'))
                .firstOrNull;
            apkSha256 = normalizeSha256(firstToken);
          }
        } catch (_) {}
      }

      final parsedNotes = rawBody
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .map((l) => l.replaceFirst(RegExp(r'^[-*•]\s*'), ''))
          .where((l) => l.isNotEmpty)
          .take(6)
          .toList();

      return AppReleaseManifest(
        latestVersion:
            '${parsedSemVer.major}.${parsedSemVer.minor}.${parsedSemVer.patch}',
        latestBuildNumber: parsedSemVer.build,
        minSupportedVersion: '1.0.0',
        releaseTitle: (data['name'] as String?)?.trim().isNotEmpty == true
            ? (data['name'] as String).trim()
            : 'Life OS $tagName',
        changelog: parsedNotes.isNotEmpty
            ? parsedNotes
            : const <String>[
                'Bản phát hành chính thức mới trên GitHub Releases.',
              ],
        apkDownloadUrl: apkUrl,
        htmlReleaseUrl:
            (data['html_url'] as String?) ?? defaultGithubReleasesUrl,
        apkSizeBytes: apkSize,
        apkSha256: apkSha256,
        publishedAt:
            DateTime.tryParse((data['published_at'] ?? '').toString()) ??
            DateTime.now(),
        sourceName: 'GitHub Releases',
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _matchesFileSha256(File file, String expectedSha256Lower) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expectedSha256Lower;
  }

  Stream<OtaDownloadProgress> downloadAndInstall(
    AppReleaseManifest manifest,
  ) async* {
    final apkUrl = manifest.apkDownloadUrl;
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        apkUrl == null ||
        apkUrl.isEmpty) {
      await _updaterBridge.openExternalUrl(manifest.htmlReleaseUrl);
      yield const OtaDownloadProgress(
        stage: OtaInstallStage.openedExternalReleasePage,
        receivedBytes: 1,
        totalBytes: 1,
      );
      return;
    }

    // F15: Enforce HTTPS + trusted release host allowlist (fail-closed)
    if (!isTrustedDownloadUrl(apkUrl)) {
      throw const AppException(
        code: 'OTA_UNTRUSTED_ORIGIN',
        message:
            'Nguồn tải gói cập nhật không nằm trong danh sách máy chủ tin cậy HTTPS. Đã chặn cài đặt.',
      );
    }

    // F15: Mandatory SHA-256 checksum on ALL OTA install paths (fail-closed)
    final expectedSha256 = normalizeSha256(manifest.apkSha256);
    if (expectedSha256 == null) {
      throw const AppException(
        code: 'OTA_MISSING_CHECKSUM',
        message:
            'Bản cập nhật thiếu mã băm SHA-256 xác thực toàn vẹn. Đã chặn tự động cài đặt để bảo vệ thiết bị.',
      );
    }

    // F15: Prevent downgrade attacks — manifest build number must exceed installed build when non-zero
    final installed = await _updaterBridge.getInstalledAppVersion();
    if (manifest.latestBuildNumber > 0 &&
        installed.buildNumber > 0 &&
        manifest.latestBuildNumber <= installed.buildNumber) {
      throw const AppException(
        code: 'OTA_DOWNGRADE_BLOCKED',
        message:
            'Phiên bản gói APK không mới hơn bản đang cài đặt trên máy. Đã hủy cập nhật.',
      );
    }

    final cacheDir = await _updaterBridge.getUpdateCacheDir();
    final safeVer = manifest.latestVersion.replaceAll(
      RegExp(r'[^0-9A-Za-z._-]'),
      '_',
    );
    final targetFile = File('$cacheDir/life-os-$safeVer.apk');

    // APP-01: Cached APK is NEVER trusted by byte size alone — MUST pass full SHA-256 verification!
    if (targetFile.existsSync()) {
      final len = targetFile.lengthSync();
      final sizeOk =
          manifest.apkSizeBytes == null || len == manifest.apkSizeBytes;
      if (sizeOk && len > 0) {
        yield OtaDownloadProgress(
          stage: OtaInstallStage.verifyingHash,
          receivedBytes: len,
          totalBytes: len,
          localApkPath: targetFile.path,
        );
        final cacheValid = await _matchesFileSha256(targetFile, expectedSha256);
        if (cacheValid) {
          final status = await _updaterBridge.installApk(targetFile.path);
          yield OtaDownloadProgress(
            stage: status == 'PERMISSION_REQUIRED'
                ? OtaInstallStage.permissionRequired
                : OtaInstallStage.installerLaunched,
            receivedBytes: len,
            totalBytes: len,
            localApkPath: targetFile.path,
          );
          return;
        }
      }
      // Tampered or corrupted cache file: purge immediately before fresh download or error!
      try {
        targetFile.deleteSync();
      } catch (_) {}
    }

    final request = http.Request('GET', Uri.parse(apkUrl));
    request.headers['User-Agent'] = 'LifeOS-SuperApp-Updater';
    final streamed = await _httpClient.send(request);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw AppException(
        code: 'OTA_DOWNLOAD_ERROR',
        message:
            'Không thể tải gói cập nhật APK (HTTP ${streamed.statusCode}).',
      );
    }

    final totalBytes = streamed.contentLength ?? manifest.apkSizeBytes ?? 0;
    final sink = targetFile.openWrite();
    var received = 0;
    var lastEmittedPercent = -1;

    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        final pct = totalBytes > 0 ? ((received * 100) ~/ totalBytes) : 0;
        if (pct != lastEmittedPercent) {
          lastEmittedPercent = pct;
          yield OtaDownloadProgress(
            stage: OtaInstallStage.downloading,
            receivedBytes: received,
            totalBytes: totalBytes,
            localApkPath: targetFile.path,
          );
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    yield OtaDownloadProgress(
      stage: OtaInstallStage.verifyingHash,
      receivedBytes: received,
      totalBytes: totalBytes > 0 ? totalBytes : received,
      localApkPath: targetFile.path,
    );

    final hashValid = await _matchesFileSha256(targetFile, expectedSha256);
    if (!hashValid) {
      if (targetFile.existsSync()) {
        targetFile.deleteSync();
      }
      throw const AppException(
        code: 'OTA_CHECKSUM_MISMATCH',
        message:
            'Mã kiểm tra toàn vẹn SHA-256 của gói APK không khớp. Đã xóa tệp và hủy cài đặt an toàn.',
      );
    }

    yield OtaDownloadProgress(
      stage: OtaInstallStage.launchingInstaller,
      receivedBytes: received,
      totalBytes: totalBytes > 0 ? totalBytes : received,
      localApkPath: targetFile.path,
    );

    final status = await _updaterBridge.installApk(targetFile.path);
    yield OtaDownloadProgress(
      stage: status == 'PERMISSION_REQUIRED'
          ? OtaInstallStage.permissionRequired
          : OtaInstallStage.installerLaunched,
      receivedBytes: received,
      totalBytes: totalBytes > 0 ? totalBytes : received,
      localApkPath: targetFile.path,
    );
  }

  Future<bool> openReleasePage(String url) =>
      _updaterBridge.openExternalUrl(url);
}
