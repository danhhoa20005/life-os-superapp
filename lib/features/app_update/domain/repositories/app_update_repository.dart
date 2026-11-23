import '../../../../core/error/app_exception.dart';
import '../entities/app_update_entities.dart';

abstract interface class AppUpdateRepository {
  Future<Result<AppUpdateCheckResult>> checkForUpdate();

  Stream<Result<OtaDownloadProgress>> downloadAndInstallUpdate(
    AppReleaseManifest manifest,
  );

  Future<Result<bool>> openReleasePage(String url);
}
