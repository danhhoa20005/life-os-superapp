import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/features/voice_assistant/data/datasources/local_asr_model_manager.dart';
import 'package:life_os/features/voice_assistant/domain/entities/voice_model_package.dart';

void main() {
  group('LocalAsrModelManager', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lifeos_asr_model_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    LocalAsrModelSpec makeSpec({
      String id = 'vosk-model-small-vn-0.4',
      String version = '0.4.0',
      required List<int> bytes,
      String? overrideSha256,
      bool commercialAllowed = true,
      String license = 'Apache-2.0',
      bool runtimeIntegrated = true,
      bool verifiedInferenceCapable = true,
    }) {
      final hash = overrideSha256 ?? sha256.convert(bytes).toString();
      return LocalAsrModelSpec(
        id: id,
        displayNameVi: 'Vosk VN Test',
        runtimeName: 'vosk',
        runtimeLicenseSpdx: 'Apache-2.0',
        modelLicenseSpdx: license,
        commercialAllowed: commercialAllowed,
        version: version,
        sizeBytes: bytes.length,
        sha256Hex: hash,
        downloadUrl: 'https://example.com/models/$id-$version.bin',
        sampleRateHz: 16000,
        supportsStreaming: true,
        languageCode: 'vi-VN',
        requiredFiles: const <String>['model.bin'],
        runtimeIntegrated: runtimeIntegrated,
        verifiedInferenceCapable: verifiedInferenceCapable,
      );
    }

    test(
      'downloads, verifies SHA-256, installs atomically, and checks integrity',
      () async {
        final payload = utf8.encode('LIFEOS_VOSK_VIETNAMESE_MODEL_V1_PAYLOAD');
        final spec = makeSpec(bytes: payload);
        final progressLog = <LocalAsrModelStatus>[];

        final client = MockClient((req) async {
          expect(req.url.scheme, 'https');
          return http.Response.bytes(payload, 200);
        });

        final manager = LocalAsrModelManager(
          rootDirectory: tempDir,
          httpClient: client,
          catalog: <LocalAsrModelSpec>[spec],
          freeSpaceBytesProvider: (_) async => 100 * 1024 * 1024,
        );

        final result = await manager.downloadModel(
          spec,
          onProgress: (p) => progressLog.add(p.status),
        );

        expect(result.status, LocalAsrModelStatus.installed);
        expect(result.installedVersion, '0.4.0');
        expect(result.downloadedBytes, payload.length);
        expect(progressLog, contains(LocalAsrModelStatus.downloading));
        expect(progressLog, contains(LocalAsrModelStatus.verifying));
        expect(progressLog, contains(LocalAsrModelStatus.installed));

        expect(await manager.verifyModelIntegrity(spec.id), isTrue);
        expect(await manager.hasVerifiedInstalledAsrModel(), isTrue);

        // Tampering installed file fails integrity check closed
        final installedModelFile = File('${result.installedPath}/model.bin');
        await installedModelFile.writeAsBytes(utf8.encode('TAMPERED_BYTES'));
        expect(await manager.verifyModelIntegrity(spec.id), isFalse);
        final afterTamper = await manager.getModelState(spec.id);
        expect(afterTamper.status, LocalAsrModelStatus.corrupted);
      },
    );

    test(
      'rejects corrupted SHA-256 download and cleans up staging file',
      () async {
        final validPayload = utf8.encode('EXPECTED_VALID_MODEL_BYTES');
        final badPayload = utf8.encode('CORRUPTED_NETWORK_BYTES');
        final spec = makeSpec(bytes: validPayload);

        final client = MockClient(
          (_) async => http.Response.bytes(badPayload, 200),
        );
        final manager = LocalAsrModelManager(
          rootDirectory: tempDir,
          httpClient: client,
          catalog: <LocalAsrModelSpec>[spec],
        );

        await expectLater(
          manager.downloadModel(spec),
          throwsA(isA<LocalAsrCorruptedModelException>()),
        );

        expect(await manager.verifyModelIntegrity(spec.id), isFalse);
        expect(await manager.hasVerifiedInstalledAsrModel(), isFalse);
        final state = await manager.getModelState(spec.id);
        expect(state.status, LocalAsrModelStatus.corrupted);
      },
    );

    test(
      'resumes partial .part download via HTTP Range header and passes SHA-256',
      () async {
        final fullPayload = utf8.encode(
          'PART_ONE_HEADER_PLUS_PART_TWO_WEIGHTS',
        );
        const splitOffset = 16;
        final firstHalf = fullPayload.sublist(0, splitOffset);
        final secondHalf = fullPayload.sublist(splitOffset);
        final spec = makeSpec(bytes: fullPayload);

        // Pre-create partial .part file simulating interrupted earlier transfer
        final stagingDir = Directory(
          '${tempDir.path}/voice_models/${spec.id}/staging',
        );
        await stagingDir.create(recursive: true);
        final partFile = File(
          '${stagingDir.path}/${spec.id}-${spec.version}.part',
        );
        await partFile.writeAsBytes(firstHalf);

        String? capturedRangeHeader;
        final client = MockClient((req) async {
          capturedRangeHeader = req.headers['Range'];
          if (capturedRangeHeader == 'bytes=$splitOffset-') {
            return http.Response.bytes(secondHalf, 206);
          }
          return http.Response('Bad Range', 400);
        });

        final manager = LocalAsrModelManager(
          rootDirectory: tempDir,
          httpClient: client,
          catalog: <LocalAsrModelSpec>[spec],
        );

        final installed = await manager.downloadModel(spec);
        expect(capturedRangeHeader, 'bytes=$splitOffset-');
        expect(installed.status, LocalAsrModelStatus.installed);
        expect(installed.downloadedBytes, fullPayload.length);
        expect(await manager.verifyModelIntegrity(spec.id), isTrue);
      },
    );

    test(
      'atomic upgrade preserves backup and rollbackModel restores previous version',
      () async {
        final v1Bytes = utf8.encode('MODEL_VERSION_1_WEIGHTS');
        final v2Bytes = utf8.encode('MODEL_VERSION_2_WEIGHTS_UPDATED');
        final specV1 = makeSpec(version: '1.0.0', bytes: v1Bytes);
        final specV2 = makeSpec(version: '2.0.0', bytes: v2Bytes);

        var serveV2 = false;
        final client = MockClient((_) async {
          return http.Response.bytes(serveV2 ? v2Bytes : v1Bytes, 200);
        });

        final manager = LocalAsrModelManager(
          rootDirectory: tempDir,
          httpClient: client,
          catalog: <LocalAsrModelSpec>[specV2],
        );

        final res1 = await manager.downloadModel(specV1);
        expect(res1.installedVersion, '1.0.0');
        expect(res1.hasRollbackBackup, isFalse);

        serveV2 = true;
        final res2 = await manager.downloadModel(specV2);
        expect(res2.installedVersion, '2.0.0');
        expect(res2.hasRollbackBackup, isTrue);

        final rolledBack = await manager.rollbackModel(specV1.id);
        expect(rolledBack, isTrue);

        final afterRollback = await manager.getModelState(specV1.id);
        expect(afterRollback.status, LocalAsrModelStatus.installed);
        expect(afterRollback.installedVersion, '1.0.0');
        expect(
          await manager.verifyModelIntegrity(specV1.id, specOverride: specV1),
          isTrue,
        );

        // Delete removes all model artifacts
        await manager.deleteModel(specV1.id);
        final afterDelete = await manager.getModelState(specV1.id);
        expect(afterDelete.status, LocalAsrModelStatus.notDownloaded);
        expect(await manager.hasVerifiedInstalledAsrModel(), isFalse);
      },
    );

    test(
      'blocks CC-BY-NC-ND-4.0 non-commercial model and enforces storage pre-check',
      () async {
        final client = MockClient(
          (_) async => http.Response('unexpected', 500),
        );
        final manager = LocalAsrModelManager(
          rootDirectory: tempDir,
          httpClient: client,
          freeSpaceBytesProvider: (_) async => 1024, // Only 1 KB free
        );

        await expectLater(
          manager.downloadModel(LocalAsrModelCatalog.sherpaZipformerViNc),
          throwsA(isA<LocalAsrLicenseBlockedException>()),
        );

        final blockedState = await manager.getModelState(
          LocalAsrModelCatalog.sherpaZipformerViNc.id,
        );
        expect(blockedState.status, LocalAsrModelStatus.licenseBlocked);

        final validSpec = makeSpec(bytes: utf8.encode('VALID_PAYLOAD'));
        await expectLater(
          manager.downloadModel(validSpec),
          throwsA(isA<LocalAsrInsufficientStorageException>()),
        );
      },
    );

    test(
      'AI-01: default 16KB placeholder catalog specs report runtimeUnavailable and NEVER claim hasVerifiedInstalledAsrModel',
      () async {
        final client = MockClient(
          (_) async => http.Response('offline_no_network_needed', 500),
        );
        final manager = LocalAsrModelManager(
          rootDirectory: tempDir,
          httpClient: client,
        );

        final models = await manager.listModels();
        expect(models.length, LocalAsrModelCatalog.defaults.length);
        for (final m in models) {
          expect(m.spec.runtimeIntegrated, isFalse);
          expect(m.spec.verifiedInferenceCapable, isFalse);
          expect(m.isUsableOffline, isFalse);
          expect(
            m.status,
            LocalAsrModelStatus.runtimeUnavailable,
            reason:
                'Expected placeholder ${m.spec.id} to report runtimeUnavailable',
          );
          expect(
            m.errorMessageVi,
            'Chưa tích hợp bộ chạy offline (Dùng Android trên máy hoặc nhập tay)',
          );
        }
        expect(await manager.hasVerifiedInstalledAsrModel(), isFalse);

        await expectLater(
          manager.downloadModel(LocalAsrModelCatalog.voskSmallVn),
          throwsA(isA<LocalAsrRuntimeUnavailableException>()),
        );
        expect(await manager.hasVerifiedInstalledAsrModel(), isFalse);
      },
    );

    test(
      'hasVerifiedInstalledAsrModel returns true ONLY when injected spec has runtimeIntegrated=true and verifiedInferenceCapable=true',
      () async {
        final payload = utf8.encode('REAL_NATIVE_ASR_MODEL_WEIGHTS');
        final unverifiedSpec = makeSpec(
          id: 'unverified-runtime-model',
          bytes: payload,
          runtimeIntegrated: true,
          verifiedInferenceCapable: false,
        );
        final verifiedSpec = makeSpec(
          id: 'verified-runtime-model',
          bytes: payload,
          runtimeIntegrated: true,
          verifiedInferenceCapable: true,
        );
        final client = MockClient(
          (_) async => http.Response.bytes(payload, 200),
        );

        final unverifiedManager = LocalAsrModelManager(
          rootDirectory: tempDir,
          httpClient: client,
          catalog: <LocalAsrModelSpec>[unverifiedSpec],
        );
        expect(
          (await unverifiedManager.listModels()).single.status,
          LocalAsrModelStatus.runtimeUnavailable,
        );
        expect(await unverifiedManager.hasVerifiedInstalledAsrModel(), isFalse);

        final verifiedManager = LocalAsrModelManager(
          rootDirectory: tempDir,
          httpClient: client,
          catalog: <LocalAsrModelSpec>[verifiedSpec],
        );
        final installed = await verifiedManager.downloadModel(verifiedSpec);
        expect(installed.status, LocalAsrModelStatus.installed);
        expect(installed.isUsableOffline, isTrue);
        expect(await verifiedManager.hasVerifiedInstalledAsrModel(), isTrue);
      },
    );
  });
}
