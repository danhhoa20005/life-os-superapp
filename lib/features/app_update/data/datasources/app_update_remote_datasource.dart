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

  final FirebaseFirestore _firestore;
  final NativeAppUpdaterBridge _updaterBridge;
  final http.Client _httpClient;

  AppUpdateRemoteDataSource({
    required FirebaseFirestore firestore,
    required NativeAppUpdaterBridge updaterBridge,
    http.Client? httpClient,
  })  : _firestore = firestore,
        _updaterBridge = updaterBridge,
        _httpClient = httpClient ?? http.Client();

  Future<InstalledAppMeta> getInstalledVersion() => _updaterBridge.getInstalledAppVersion();

  Future<AppReleaseManifest?> fetchLatestManifest() async {
    final results = await Future.wait<AppReleaseManifest?>([
      _fetchFromFirestore(),
      _fetchFromGithubReleases(),
    ]);

    AppReleaseManifest? best;
    for (final candidate in results) {
      if (candidate == null) continue;
      if (best == null || candidate.semanticVersion.isNewerThan(best.semanticVersion)) {
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
          ? rawChangelog.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
          : <String>['Cải thiện hiệu năng, bảo mật và trải nghiệm người dùng.'];

      final pubTs = d['publishedAt'];
      final publishedAt = pubTs is Timestamp
          ? pubTs.toDate()
          : DateTime.tryParse((d['publishedAt'] ?? '').toString()) ?? DateTime.now();

      return AppReleaseManifest(
        latestVersion: latestVersion,
        latestBuildNumber: (d['latestBuildNumber'] as num?)?.toInt() ?? 0,
        minSupportedVersion: (d['minSupportedVersion'] as String?) ?? '1.0.0',
        releaseTitle: (d['releaseTitle'] as String?) ?? 'Life OS v$latestVersion',
        changelog: changelog,
        apkDownloadUrl: d['apkDownloadUrl'] as String?,
        htmlReleaseUrl: (d['htmlReleaseUrl'] as String?) ?? defaultGithubReleasesUrl,
        apkSizeBytes: (d['apkSizeBytes'] as num?)?.toInt(),
        apkSha256: d['apkSha256'] as String?,
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
      final assets = data['assets'];
      if (assets is Iterable) {
        for (final asset in assets) {
          if (asset is Map<String, dynamic>) {
            final name = (asset['name'] as String?)?.toLowerCase() ?? '';
            if (name.endsWith('.apk')) {
              apkUrl = asset['browser_download_url'] as String?;
              apkSize = (asset['size'] as num?)?.toInt();
              break;
            }
          }
        }
      }

      final rawBody = (data['body'] as String?) ?? '';
      final parsedNotes = rawBody
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .map((l) => l.replaceFirst(RegExp(r'^[-*•]\s*'), ''))
          .where((l) => l.isNotEmpty)
          .take(6)
          .toList();

      return AppReleaseManifest(
        latestVersion: '${parsedSemVer.major}.${parsedSemVer.minor}.${parsedSemVer.patch}',
        latestBuildNumber: parsedSemVer.build,
        minSupportedVersion: '1.0.0',
        releaseTitle: (data['name'] as String?)?.trim().isNotEmpty == true
            ? (data['name'] as String).trim()
            : 'Life OS $tagName',
        changelog: parsedNotes.isNotEmpty
            ? parsedNotes
            : const <String>['Bản phát hành chính thức mới trên GitHub Releases.'],
        apkDownloadUrl: apkUrl,
        htmlReleaseUrl: (data['html_url'] as String?) ?? defaultGithubReleasesUrl,
        apkSizeBytes: apkSize,
        publishedAt: DateTime.tryParse((data['published_at'] ?? '').toString()) ?? DateTime.now(),
        sourceName: 'GitHub Releases',
      );
    } catch (_) {
      return null;
    }
  }

  Stream<OtaDownloadProgress> downloadAndInstall(AppReleaseManifest manifest) async* {
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

    final cacheDir = await _updaterBridge.getUpdateCacheDir();
    final safeVer = manifest.latestVersion.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final targetFile = File('$cacheDir/life-os-$safeVer.apk');

    // If the exact APK is already downloaded and matches size/hash, skip re-downloading!
    if (targetFile.existsSync()) {
      final len = targetFile.lengthSync();
      final matchesExpected = manifest.apkSizeBytes == null || len == manifest.apkSizeBytes;
      if (matchesExpected && len > 1024 * 100) {
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

    final request = http.Request('GET', Uri.parse(apkUrl));
    request.headers['User-Agent'] = 'LifeOS-SuperApp-Updater';
    final streamed = await _httpClient.send(request);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw AppException(
        code: 'OTA_DOWNLOAD_ERROR',
        message: 'Không thể tải gói cập nhật APK (HTTP ${streamed.statusCode}).',
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

    if (manifest.apkSha256 != null && manifest.apkSha256!.trim().isNotEmpty) {
      yield OtaDownloadProgress(
        stage: OtaInstallStage.verifyingHash,
        receivedBytes: received,
        totalBytes: totalBytes > 0 ? totalBytes : received,
        localApkPath: targetFile.path,
      );
      final digest = await sha256.bind(targetFile.openRead()).first;
      if (digest.toString().toLowerCase() != manifest.apkSha256!.trim().toLowerCase()) {
        if (targetFile.existsSync()) {
          targetFile.deleteSync();
        }
        throw const AppException(
          code: 'OTA_CHECKSUM_MISMATCH',
          message: 'Mã kiểm tra toàn vẹn SHA-256 của gói APK không khớp. Đã hủy cài đặt an toàn.',
        );
      }
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

  Future<bool> openReleasePage(String url) => _updaterBridge.openExternalUrl(url);
}
