import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/error/error_mapper.dart';
import 'package:life_os/core/services/native_app_updater_bridge.dart';
import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:life_os/features/app_update/data/datasources/app_update_remote_datasource.dart';
import 'package:life_os/features/app_update/data/repositories/app_update_repository_impl.dart';
import 'package:life_os/features/app_update/domain/entities/app_update_entities.dart';
import 'package:life_os/features/app_update/domain/repositories/app_update_repository.dart';
import 'package:life_os/features/app_update/domain/usecases/app_update_usecases.dart';
import 'package:life_os/features/app_update/presentation/bloc/app_update_bloc.dart';
import 'package:life_os/features/app_update/presentation/widgets/app_update_widgets.dart';

class _RejectingUpdaterBridge extends NativeAppUpdaterBridge {
  final String cacheDirPath;
  final String errorCode;
  final String errorMessage;

  const _RejectingUpdaterBridge({
    required this.cacheDirPath,
    required this.errorCode,
    required this.errorMessage,
  }) : super(
         fixedDistributionFlavor: 'github',
         fixedGitHubOtaEnabled: true,
         fixedInstalledMeta: const InstalledAppMeta(
           versionName: '3.27.0',
           buildNumber: 45,
           packageName: 'vn.lifeos.app.life_os',
           abi: 'arm64-v8a',
         ),
       );

  @override
  Future<String> getUpdateCacheDir() async => cacheDirPath;

  @override
  Future<String> installApk(String filePath) async {
    throw AppException(code: errorCode, message: errorMessage);
  }
}

class _InMemoryRejectingUpdateRepository implements AppUpdateRepository {
  final String rejectionCode;
  final String rejectionMessage;

  const _InMemoryRejectingUpdateRepository({
    required this.rejectionCode,
    required this.rejectionMessage,
  });

  @override
  Future<Result<AppUpdateCheckResult>> checkForUpdate() async {
    return Success(
      AppUpdateCheckResult(
        installedVersion: '3.27.0',
        installedBuildNumber: 45,
        manifest: AppReleaseManifest(
          latestVersion: '3.28.0',
          latestBuildNumber: 46,
          minSupportedVersion: '1.0.0',
          releaseTitle: 'LifeOS v3.28.0',
          changelog: const ['Khắc phục bảo mật ký số OTA'],
          apkDownloadUrl:
              'https://github.com/danhhoa20005/life-os-superapp/releases/download/v3.28.0/app.apk',
          htmlReleaseUrl: AppUpdateRemoteDataSource.defaultGithubReleasesUrl,
          apkSizeBytes: 1024 * 1024,
          apkSha256: 'a' * 64,
          publishedAt: DateTime(2026, 11, 25),
          sourceName: 'GitHub Releases',
        ),
        hasUpdate: true,
        isForceUpdate: false,
        checkedAt: DateTime(2026, 11, 25),
      ),
    );
  }

  @override
  Stream<Result<OtaDownloadProgress>> downloadAndInstallUpdate(
    AppReleaseManifest manifest,
  ) async* {
    yield const Success(
      OtaDownloadProgress(
        stage: OtaInstallStage.downloading,
        receivedBytes: 512,
        totalBytes: 1024,
      ),
    );
    yield Err(
      ErrorMapper.map(
        AppException(code: rejectionCode, message: rejectionMessage),
      ),
    );
  }

  @override
  Future<Result<bool>> openReleasePage(String url) async => const Success(true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const updaterChannel = MethodChannel('vn.lifeos.app/app_updater');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(updaterChannel, null);
  });

  group('NativeAppUpdaterBridge tri-state signature handling (Finding 8)', () {
    test(
      'verifyApkSignature parses MATCH, MISMATCH, and UNREADABLE tri-state responses over MethodChannel',
      () async {
        const bridge = NativeAppUpdaterBridge(
          fixedDistributionFlavor: 'github',
          fixedGitHubOtaEnabled: true,
          forceAndroidPlatformForTest: true,
        );

        for (final status in ['MATCH', 'MISMATCH', 'UNREADABLE']) {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(updaterChannel, (call) async {
                if (call.method == 'verifyApkSignature') {
                  return <String, dynamic>{
                    'signatureStatus': status,
                    'status': status,
                    'valid': status == 'MATCH',
                    'errorCode': status == 'MATCH' ? null : 'CERT_$status',
                    'reason': status == 'MATCH'
                        ? null
                        : 'Lý do kiểm tra chữ ký: $status',
                  };
                }
                return null;
              });

          final outcome = await bridge.verifyApkSignature('/tmp/test.apk');
          expect(outcome.status, switch (status) {
            'MATCH' => AppSignatureVerificationStatus.match,
            'MISMATCH' => AppSignatureVerificationStatus.mismatch,
            _ => AppSignatureVerificationStatus.unreadable,
          });
          expect(outcome.isMatch, status == 'MATCH');
        }
      },
    );

    test(
      'installApk converts PlatformException CERT_MISMATCH and CERT_UNREADABLE into AppException with Vietnamese reason',
      () async {
        const bridge = NativeAppUpdaterBridge(
          fixedDistributionFlavor: 'github',
          fixedGitHubOtaEnabled: true,
          forceAndroidPlatformForTest: true,
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(updaterChannel, (call) async {
              if (call.method == 'installApk') {
                throw PlatformException(
                  code: 'CERT_UNREADABLE',
                  message:
                      'Không thể đọc chứng chỉ ký số từ tệp APK mới (APP-03).',
                  details: <String, dynamic>{
                    'signatureStatus': 'UNREADABLE',
                    'reason':
                        'Không thể đọc chứng chỉ ký số từ tệp APK mới (APP-03).',
                  },
                );
              }
              return null;
            });

        await expectLater(
          bridge.installApk('/tmp/corrupt.apk'),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', 'OTA_CERT_UNREADABLE')
                .having(
                  (e) => e.message,
                  'message',
                  contains('Không thể đọc chứng chỉ ký số'),
                ),
          ),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(updaterChannel, (call) async {
              if (call.method == 'installApk') {
                throw PlatformException(
                  code: 'CERT_MISMATCH',
                  message:
                      'Chứng chỉ ký của gói APK mới không khớp với phiên bản đang cài đặt (APP-03).',
                  details: <String, dynamic>{
                    'signatureStatus': 'MISMATCH',
                    'reason':
                        'Chứng chỉ ký của gói APK mới không khớp với phiên bản đang cài đặt (APP-03).',
                  },
                );
              }
              return null;
            });

        await expectLater(
          bridge.installApk('/tmp/wrong_key.apk'),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', 'OTA_CERT_MISMATCH')
                .having(
                  (e) => e.message,
                  'message',
                  contains('Chứng chỉ ký của gói APK mới không khớp'),
                ),
          ),
        );
      },
    );

    test(
      'AppUpdateBloc surfaces exact Vietnamese reason when APK signature is UNREADABLE',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final tempDir = await Directory.systemTemp.createTemp(
          'lifeos_ota_sig_ui_',
        );

        final apkBytes = utf8.encode('SIGNED_BY_ROGUE_OR_MISSING_CERT');
        final sha = sha256.convert(apkBytes).toString();
        final manifest = AppReleaseManifest(
          latestVersion: '3.28.0',
          latestBuildNumber: 46,
          minSupportedVersion: '1.0.0',
          releaseTitle: 'LifeOS v3.28.0',
          changelog: const ['Security release'],
          apkDownloadUrl:
              'https://github.com/danhhoa20005/life-os-superapp/releases/download/v3.28.0/app.apk',
          htmlReleaseUrl: AppUpdateRemoteDataSource.defaultGithubReleasesUrl,
          apkSizeBytes: apkBytes.length,
          apkSha256: sha,
          publishedAt: DateTime(2026, 11, 25),
          sourceName: 'GitHub Releases',
        );

        const expectedReason =
            'Không thể đọc chứng chỉ ký số từ tệp APK mới. Tệp có thể thiếu chữ ký hoặc bị hỏng (APP-03).';
        final bridge = _RejectingUpdaterBridge(
          cacheDirPath: tempDir.path,
          errorCode: 'OTA_CERT_UNREADABLE',
          errorMessage: expectedReason,
        );
        final ds = AppUpdateRemoteDataSource(
          firestore: FakeFirebaseFirestore(),
          updaterBridge: bridge,
          httpClient: MockClient((req) async {
            if (req.url.host == 'api.github.com') {
              return http.Response(
                jsonEncode({
                  'tag_name': 'v3.28.0+46',
                  'name': manifest.releaseTitle,
                  'body': 'SHA-256: $sha',
                  'html_url': manifest.htmlReleaseUrl,
                  'published_at': '2026-11-25T10:00:00Z',
                  'assets': [
                    {
                      'name': 'life-os-v3.28.0-github-arm64-v8a.apk',
                      'browser_download_url': manifest.apkDownloadUrl,
                      'size': apkBytes.length,
                      'digest': 'sha256:$sha',
                    },
                  ],
                }),
                200,
              );
            }
            return http.Response.bytes(apkBytes, 200);
          }),
        );
        final repo = AppUpdateRepositoryImpl(ds);
        final bloc = AppUpdateBloc(
          checkForUpdate: CheckForAppUpdateUseCase(repo),
          downloadAndInstall: DownloadAndInstallUpdateUseCase(repo),
          openReleasePage: OpenReleasePageUseCase(repo),
        );
        addTearDown(() async {
          await bloc.close();
          if (tempDir.existsSync()) await tempDir.delete(recursive: true);
        });

        final availableFuture = bloc.stream.firstWhere(
          (s) => s.status == AppUpdateStatus.updateAvailable,
        );
        bloc.add(const AppUpdateCheckRequested(silent: false));
        final availableState = await availableFuture;
        expect(availableState.hasUpdate, isTrue);

        final failureFuture = bloc.stream.firstWhere(
          (s) => s.status == AppUpdateStatus.failure,
        );
        bloc.add(const AppUpdateDownloadRequested());
        final failureState = await failureFuture;

        expect(failureState.status, AppUpdateStatus.failure);
        expect(failureState.failure?.message, expectedReason);
      },
    );
  });

  testWidgets(
    'AppUpdateBanner & AppUpdateSettingsCard render Vietnamese signature rejection error cleanly at 360x800 without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const rejectionMsg =
          'Chứng chỉ ký của gói APK mới không khớp với phiên bản đang cài đặt (APP-03).';
      const repo = _InMemoryRejectingUpdateRepository(
        rejectionCode: 'OTA_CERT_MISMATCH',
        rejectionMessage: rejectionMsg,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => LifeOsTopToastHost(child: child!),
          home: BlocProvider<AppUpdateBloc>(
            create: (_) => AppUpdateBloc(
              checkForUpdate: const CheckForAppUpdateUseCase(repo),
              downloadAndInstall: const DownloadAndInstallUpdateUseCase(repo),
              openReleasePage: const OpenReleasePageUseCase(repo),
            )..add(const AppUpdateCheckRequested(silent: false)),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [AppUpdateBanner(), AppUpdateSettingsCard()],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ota_install_now_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ota_install_now_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ota_banner_error_message')), findsOneWidget);
      expect(
        find.byKey(const Key('ota_settings_error_message')),
        findsOneWidget,
      );
      expect(find.text(rejectionMsg), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
