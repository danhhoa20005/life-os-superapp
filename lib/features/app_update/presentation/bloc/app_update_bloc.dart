import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/app_update_entities.dart';
import '../../domain/usecases/app_update_usecases.dart';

sealed class AppUpdateEvent extends Equatable {
  const AppUpdateEvent();

  @override
  List<Object?> get props => [];
}

final class AppUpdateCheckRequested extends AppUpdateEvent {
  final bool silent;

  const AppUpdateCheckRequested({this.silent = true});

  @override
  List<Object?> get props => [silent];
}

final class AppUpdateDownloadRequested extends AppUpdateEvent {
  const AppUpdateDownloadRequested();
}

final class AppUpdateBannerDismissed extends AppUpdateEvent {
  const AppUpdateBannerDismissed();
}

final class AppUpdateOpenReleasePageRequested extends AppUpdateEvent {
  final String url;

  const AppUpdateOpenReleasePageRequested(this.url);

  @override
  List<Object?> get props => [url];
}

enum AppUpdateStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  readyToInstall,
  permissionRequired,
  failure,
}

final class AppUpdateState extends Equatable {
  final AppUpdateStatus status;
  final String installedVersion;
  final int installedBuildNumber;
  final AppReleaseManifest? manifest;
  final bool hasUpdate;
  final bool isForceUpdate;
  final bool isBannerDismissed;
  final OtaDownloadProgress? downloadProgress;
  final Failure? failure;
  final String? infoMessage;

  const AppUpdateState({
    this.status = AppUpdateStatus.idle,
    this.installedVersion = '1.0.0',
    this.installedBuildNumber = 1,
    this.manifest,
    this.hasUpdate = false,
    this.isForceUpdate = false,
    this.isBannerDismissed = false,
    this.downloadProgress,
    this.failure,
    this.infoMessage,
  });

  String get installedDisplay => '$installedVersion+$installedBuildNumber';

  AppUpdateState copyWith({
    AppUpdateStatus? status,
    String? installedVersion,
    int? installedBuildNumber,
    AppReleaseManifest? manifest,
    bool? hasUpdate,
    bool? isForceUpdate,
    bool? isBannerDismissed,
    OtaDownloadProgress? downloadProgress,
    bool clearProgress = false,
    Failure? failure,
    bool clearFailure = false,
    String? infoMessage,
    bool clearInfo = false,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      installedVersion: installedVersion ?? this.installedVersion,
      installedBuildNumber: installedBuildNumber ?? this.installedBuildNumber,
      manifest: manifest ?? this.manifest,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      isForceUpdate: isForceUpdate ?? this.isForceUpdate,
      isBannerDismissed: isBannerDismissed ?? this.isBannerDismissed,
      downloadProgress: clearProgress ? null : (downloadProgress ?? this.downloadProgress),
      failure: clearFailure ? null : (failure ?? this.failure),
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        installedVersion,
        installedBuildNumber,
        manifest,
        hasUpdate,
        isForceUpdate,
        isBannerDismissed,
        downloadProgress,
        failure,
        infoMessage,
      ];
}

class AppUpdateBloc extends Bloc<AppUpdateEvent, AppUpdateState> {
  final CheckForAppUpdateUseCase _checkForUpdate;
  final DownloadAndInstallUpdateUseCase _downloadAndInstall;
  final OpenReleasePageUseCase _openReleasePage;

  AppUpdateBloc({
    required CheckForAppUpdateUseCase checkForUpdate,
    required DownloadAndInstallUpdateUseCase downloadAndInstall,
    required OpenReleasePageUseCase openReleasePage,
  })  : _checkForUpdate = checkForUpdate,
        _downloadAndInstall = downloadAndInstall,
        _openReleasePage = openReleasePage,
        super(const AppUpdateState()) {
    on<AppUpdateCheckRequested>(_onCheckRequested, transformer: droppable());
    on<AppUpdateDownloadRequested>(_onDownloadRequested, transformer: droppable());
    on<AppUpdateBannerDismissed>(_onBannerDismissed);
    on<AppUpdateOpenReleasePageRequested>(_onOpenReleasePageRequested, transformer: droppable());
  }

  Future<void> _onCheckRequested(
    AppUpdateCheckRequested event,
    Emitter<AppUpdateState> emit,
  ) async {
    emit(
      state.copyWith(
        status: AppUpdateStatus.checking,
        clearFailure: true,
        clearInfo: true,
      ),
    );
    final result = await _checkForUpdate(const NoParams());
    result.fold(
      (failure) => emit(
        state.copyWith(
          status: AppUpdateStatus.failure,
          failure: event.silent ? null : failure,
        ),
      ),
      (check) => emit(
        state.copyWith(
          status: check.hasUpdate ? AppUpdateStatus.updateAvailable : AppUpdateStatus.upToDate,
          installedVersion: check.installedVersion,
          installedBuildNumber: check.installedBuildNumber,
          manifest: check.manifest,
          hasUpdate: check.hasUpdate,
          isForceUpdate: check.isForceUpdate,
          isBannerDismissed: check.hasUpdate ? false : state.isBannerDismissed,
          infoMessage: !event.silent
              ? (check.hasUpdate
                  ? 'Phát hiện phiên bản mới v${check.manifest?.latestVersion}!'
                  : 'Bạn đang sử dụng phiên bản mới nhất (${check.installedVersion}+${check.installedBuildNumber}).')
              : null,
        ),
      ),
    );
  }

  Future<void> _onDownloadRequested(
    AppUpdateDownloadRequested event,
    Emitter<AppUpdateState> emit,
  ) async {
    final targetManifest = state.manifest;
    if (targetManifest == null) return;

    emit(
      state.copyWith(
        status: AppUpdateStatus.downloading,
        clearFailure: true,
        clearInfo: true,
      ),
    );

    await emit.forEach(
      _downloadAndInstall(targetManifest),
      onData: (res) => res.fold(
        (failure) => state.copyWith(
          status: AppUpdateStatus.failure,
          failure: failure,
        ),
        (progress) {
          return switch (progress.stage) {
            OtaInstallStage.downloading || OtaInstallStage.verifyingHash || OtaInstallStage.launchingInstaller =>
              state.copyWith(
                status: AppUpdateStatus.downloading,
                downloadProgress: progress,
              ),
            OtaInstallStage.permissionRequired => state.copyWith(
                status: AppUpdateStatus.permissionRequired,
                downloadProgress: progress,
                infoMessage:
                    'Hãy bật "Cho phép cài đặt ứng dụng từ nguồn này" rồi bấm Cài đặt lại.',
              ),
            OtaInstallStage.installerLaunched => state.copyWith(
                status: AppUpdateStatus.readyToInstall,
                downloadProgress: progress,
                infoMessage: 'Đã mở trình cài đặt hệ thống Android cho bản cập nhật mới!',
              ),
            OtaInstallStage.openedExternalReleasePage => state.copyWith(
                status: AppUpdateStatus.updateAvailable,
                downloadProgress: progress,
                infoMessage: 'Đã mở trang tải bản phát hành chính thức trên trình duyệt.',
              ),
          };
        },
      ),
    );
  }

  void _onBannerDismissed(
    AppUpdateBannerDismissed event,
    Emitter<AppUpdateState> emit,
  ) {
    if (state.isForceUpdate) return;
    emit(state.copyWith(isBannerDismissed: true));
  }

  Future<void> _onOpenReleasePageRequested(
    AppUpdateOpenReleasePageRequested event,
    Emitter<AppUpdateState> emit,
  ) async {
    await _openReleasePage(event.url);
  }
}
