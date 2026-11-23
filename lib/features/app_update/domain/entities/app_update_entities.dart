import 'package:equatable/equatable.dart';

class SemanticAppVersion extends Equatable
    implements Comparable<SemanticAppVersion> {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const SemanticAppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.build = 0,
  });

  factory SemanticAppVersion.parse(String raw, {int fallbackBuild = 0}) {
    final cleaned = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final buildSplit = cleaned.split('+');
    final corePart = buildSplit.first.split('-').first;
    final parsedBuild = buildSplit.length > 1
        ? (int.tryParse(buildSplit[1].trim()) ?? fallbackBuild)
        : fallbackBuild;

    final nums = corePart.split('.');
    final major = nums.isNotEmpty ? (int.tryParse(nums[0]) ?? 1) : 1;
    final minor = nums.length > 1 ? (int.tryParse(nums[1]) ?? 0) : 0;
    final patch = nums.length > 2 ? (int.tryParse(nums[2]) ?? 0) : 0;

    return SemanticAppVersion(
      major: major,
      minor: minor,
      patch: patch,
      build: parsedBuild,
    );
  }

  @override
  int compareTo(SemanticAppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  bool isNewerThan(SemanticAppVersion other) => compareTo(other) > 0;

  bool isOlderThanCore(SemanticAppVersion minSupported) {
    if (major != minSupported.major) return major < minSupported.major;
    if (minor != minSupported.minor) return minor < minSupported.minor;
    return patch < minSupported.patch;
  }

  String get formatted =>
      build > 0 ? '$major.$minor.$patch+$build' : '$major.$minor.$patch';

  @override
  List<Object?> get props => [major, minor, patch, build];
}

class AppReleaseManifest extends Equatable {
  final String latestVersion;
  final int latestBuildNumber;
  final String minSupportedVersion;
  final String releaseTitle;
  final List<String> changelog;
  final String? apkDownloadUrl;
  final String htmlReleaseUrl;
  final int? apkSizeBytes;
  final String? apkSha256;
  final DateTime publishedAt;
  final String sourceName;

  const AppReleaseManifest({
    required this.latestVersion,
    required this.latestBuildNumber,
    this.minSupportedVersion = '1.0.0',
    required this.releaseTitle,
    required this.changelog,
    this.apkDownloadUrl,
    required this.htmlReleaseUrl,
    this.apkSizeBytes,
    this.apkSha256,
    required this.publishedAt,
    required this.sourceName,
  });

  SemanticAppVersion get semanticVersion =>
      SemanticAppVersion.parse(latestVersion, fallbackBuild: latestBuildNumber);

  String? get formattedSizeMb {
    final bytes = apkSizeBytes;
    if (bytes == null || bytes <= 0) return null;
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  List<Object?> get props => [
    latestVersion,
    latestBuildNumber,
    minSupportedVersion,
    releaseTitle,
    changelog,
    apkDownloadUrl,
    htmlReleaseUrl,
    apkSizeBytes,
    apkSha256,
    publishedAt,
    sourceName,
  ];
}

class AppUpdateCheckResult extends Equatable {
  final String installedVersion;
  final int installedBuildNumber;
  final AppReleaseManifest? manifest;
  final bool hasUpdate;
  final bool isForceUpdate;
  final DateTime checkedAt;

  const AppUpdateCheckResult({
    required this.installedVersion,
    required this.installedBuildNumber,
    this.manifest,
    required this.hasUpdate,
    required this.isForceUpdate,
    required this.checkedAt,
  });

  @override
  List<Object?> get props => [
    installedVersion,
    installedBuildNumber,
    manifest,
    hasUpdate,
    isForceUpdate,
    checkedAt,
  ];
}

enum OtaInstallStage {
  downloading,
  verifyingHash,
  launchingInstaller,
  installerLaunched,
  permissionRequired,
  openedExternalReleasePage,
}

class OtaDownloadProgress extends Equatable {
  final OtaInstallStage stage;
  final int receivedBytes;
  final int totalBytes;
  final String? localApkPath;

  const OtaDownloadProgress({
    required this.stage,
    required this.receivedBytes,
    required this.totalBytes,
    this.localApkPath,
  });

  double get fraction {
    if (totalBytes <= 0) return 0.0;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  int get percent => (fraction * 100).round();

  @override
  List<Object?> get props => [stage, receivedBytes, totalBytes, localApkPath];
}
