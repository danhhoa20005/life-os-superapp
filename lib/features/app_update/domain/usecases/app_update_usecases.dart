import '../../../../core/error/app_exception.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/app_update_entities.dart';
import '../repositories/app_update_repository.dart';

class CheckForAppUpdateUseCase
    implements UseCase<AppUpdateCheckResult, NoParams> {
  final AppUpdateRepository _repository;
  const CheckForAppUpdateUseCase(this._repository);

  @override
  Future<Result<AppUpdateCheckResult>> call(NoParams params) {
    return _repository.checkForUpdate();
  }
}

class DownloadAndInstallUpdateUseCase {
  final AppUpdateRepository _repository;
  const DownloadAndInstallUpdateUseCase(this._repository);

  Stream<Result<OtaDownloadProgress>> call(AppReleaseManifest manifest) {
    return _repository.downloadAndInstallUpdate(manifest);
  }
}

class OpenReleasePageUseCase implements UseCase<bool, String> {
  final AppUpdateRepository _repository;
  const OpenReleasePageUseCase(this._repository);

  @override
  Future<Result<bool>> call(String url) {
    return _repository.openReleasePage(url);
  }
}
