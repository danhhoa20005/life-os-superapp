import '../entities/voice_model_package.dart';

/// Domain contract for offline local ASR & VAD model package management.
abstract interface class LocalAsrModelRepository {
  Future<List<LocalAsrModelInstallState>> listModels();

  Future<LocalAsrModelInstallState> getModelState(String modelId);

  Future<bool> hasVerifiedInstalledAsrModel();

  Future<LocalAsrModelInstallState> downloadModel(
    LocalAsrModelSpec spec, {
    void Function(LocalAsrDownloadProgress progress)? onProgress,
    bool enforceCommercialLicense = true,
  });

  Future<bool> verifyModelIntegrity(
    String modelId, {
    LocalAsrModelSpec? specOverride,
  });

  Future<bool> rollbackModel(String modelId);

  Future<void> deleteModel(String modelId);
}
