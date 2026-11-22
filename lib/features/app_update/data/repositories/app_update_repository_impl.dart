import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/app_update_entities.dart';
import '../../domain/repositories/app_update_repository.dart';
import '../datasources/app_update_remote_datasource.dart';

class AppUpdateRepositoryImpl implements AppUpdateRepository {
  final AppUpdateRemoteDataSource _remoteDataSource;

  const AppUpdateRepositoryImpl(this._remoteDataSource);

  @override
  Future<Result<AppUpdateCheckResult>> checkForUpdate() async {
    try {
      final installed = await _remoteDataSource.getInstalledVersion();
      final manifest = await _remoteDataSource.fetchLatestManifest();
      final now = DateTime.now();

      if (manifest == null) {
        return Success(
          AppUpdateCheckResult(
            installedVersion: installed.versionName,
            installedBuildNumber: installed.buildNumber,
            hasUpdate: false,
            isForceUpdate: false,
            checkedAt: now,
          ),
        );
      }

      final currentSemVer = SemanticAppVersion.parse(
        installed.versionName,
        fallbackBuild: installed.buildNumber,
      );
      final latestSemVer = manifest.semanticVersion;
      final minSemVer = SemanticAppVersion.parse(manifest.minSupportedVersion);

      final hasUpdate = latestSemVer.isNewerThan(currentSemVer);
      final isForceUpdate = hasUpdate && currentSemVer.isOlderThanCore(minSemVer);

      return Success(
        AppUpdateCheckResult(
          installedVersion: installed.versionName,
          installedBuildNumber: installed.buildNumber,
          manifest: manifest,
          hasUpdate: hasUpdate,
          isForceUpdate: isForceUpdate,
          checkedAt: now,
        ),
      );
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Stream<Result<OtaDownloadProgress>> downloadAndInstallUpdate(
    AppReleaseManifest manifest,
  ) async* {
    try {
      await for (final progress in _remoteDataSource.downloadAndInstall(manifest)) {
        yield Success(progress);
      }
    } catch (e) {
      yield Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<bool>> openReleasePage(String url) async {
    try {
      final ok = await _remoteDataSource.openReleasePage(url);
      return Success(ok);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
