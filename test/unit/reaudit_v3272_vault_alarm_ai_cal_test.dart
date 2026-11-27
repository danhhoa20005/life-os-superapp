import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/services/fcm_banking_messaging_service.dart';
import 'package:life_os/core/services/file_storage_service.dart';
import 'package:life_os/core/services/native_alarm_scheduler_bridge.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/services/personal_alarm_service.dart';
import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:life_os/features/calendar/data/datasources/google_calendar_api_datasource.dart';
import 'package:life_os/features/calendar/data/repositories/calendar_repository_impl.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/documents/data/repositories/document_vault_repository_impl.dart';
import 'package:life_os/features/documents/domain/entities/document_vault_entity.dart';
import 'package:life_os/features/documents/domain/repositories/document_vault_repository.dart';
import 'package:life_os/features/financial_ai/data/datasources/gemini_remote_datasource.dart';
import 'package:life_os/features/financial_ai/domain/entities/gemini_copilot_entities.dart';
import 'package:life_os/features/voice_assistant/data/datasources/local_asr_model_manager.dart';
import 'package:life_os/features/voice_assistant/data/datasources/voice_native_channel_datasource.dart';
import 'package:life_os/features/voice_assistant/data/repositories/voice_capability_repository_impl.dart';
import 'package:life_os/features/voice_assistant/domain/entities/voice_engine_capability.dart';
import 'package:life_os/features/voice_assistant/domain/entities/voice_event.dart';
import 'package:life_os/features/voice_assistant/domain/entities/voice_model_package.dart';
import 'package:life_os/features/voice_assistant/domain/services/monotonic_clock.dart';
import 'package:life_os/features/voice_assistant/domain/services/speech_engine_adapter.dart';
import 'package:life_os/features/voice_assistant/domain/services/voice_session_coordinator.dart';
import 'package:life_os/features/voice_assistant/presentation/bloc/voice_assistant_bloc.dart';
import 'package:life_os/features/voice_assistant/presentation/pages/voice_diagnostics_page.dart';

class _FailingThenRecoveringFileStorage implements FileStorageService {
  bool shouldThrowOnDelete = false;
  bool shouldReturnFalseOnDelete = false;
  final List<String?> deletedAttachmentIds = <String?>[];

  @override
  bool get isCloudObjectStorageEnabled => false;

  @override
  bool get isLocalDeviceVaultEnabled => true;

  @override
  Future<Result<StoredFileReference>> uploadUserAttachment({
    required String userId,
    required String folder,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<Uint8List?>> readLocalAttachmentBytes({
    required String userId,
    String? storageKey,
    String? attachmentId,
    String? expectedPlaintextSha256,
  }) async => const Success(null);

  @override
  Future<Result<void>> deleteUserAttachment({
    required String userId,
    required String storageKey,
  }) async => const Success(null);

  @override
  Future<bool> deleteAttachmentForUser({
    required String userId,
    String? attachmentId,
    String? legacyLocalPath,
    String? legacyStorageKey,
  }) async {
    if (shouldThrowOnDelete) {
      throw const FileSystemException('Simulated disk lock');
    }
    if (shouldReturnFalseOnDelete) {
      return false;
    }
    deletedAttachmentIds.add(attachmentId);
    return true;
  }
}

// ignore: subtype_of_sealed_class
class _CountingWriteBatch extends Fake implements WriteBatch {
  final WriteBatch _inner;
  final List<int> _committedSizes;
  int _ops = 0;

  _CountingWriteBatch(this._inner, this._committedSizes);

  @override
  void delete(DocumentReference<Object?> document) {
    _ops += 1;
    _inner.delete(document);
  }

  @override
  Future<void> commit() {
    _committedSizes.add(_ops);
    return _inner.commit();
  }
}

// ignore: subtype_of_sealed_class
class _SpyBatchFirestore extends Fake implements FirebaseFirestore {
  final FakeFirebaseFirestore _inner;
  final List<int> committedBatchSizes = <int>[];

  _SpyBatchFirestore(this._inner);

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _inner.collection(collectionPath);

  @override
  WriteBatch batch() =>
      _CountingWriteBatch(_inner.batch(), committedBatchSizes);
}

class _Throwing404GoogleCalendarApi extends GoogleCalendarApiDataSource {
  final int statusToThrow;
  bool deleteCalled = false;

  _Throwing404GoogleCalendarApi({this.statusToThrow = 404})
    : super(
        tokenProviderOverride: ({required interactive}) async => 'tok_valid',
      );

  @override
  Future<void> deleteSecondaryCalendar({
    required String accessToken,
    required String googleCalendarId,
  }) async {
    deleteCalled = true;
    throw AppException(
      code: 'GCAL_DELETE_CALENDAR_ERROR',
      message:
          'Không thể xóa bộ lịch trên Google Calendar (HTTP $statusToThrow).',
    );
  }
}

class _SequencedFcmDriver implements FcmPlatformDriver {
  final List<String> events = <String>[];
  final StreamController<String> regCtrl = StreamController<String>.broadcast();
  final StreamController<IncomingBankingPushPayload> fgCtrl =
      StreamController<IncomingBankingPushPayload>.broadcast();
  final StreamController<IncomingBankingPushPayload> openCtrl =
      StreamController<IncomingBankingPushPayload>.broadcast();
  IncomingBankingPushPayload? coldStart;
  final String tokenToEmit;

  _SequencedFcmDriver({this.tokenToEmit = 'fcm_tok_default'});

  @override
  Future<bool> requestPushPermission() async => true;

  @override
  Future<void> registerDevice() async {
    events.add('registerDevice');
    regCtrl.add(tokenToEmit);
  }

  @override
  Future<void> unregisterDevice() async {
    events.add('unregisterDevice');
  }

  @override
  Stream<String> get onRegistered => regCtrl.stream;

  @override
  Stream<IncomingBankingPushPayload> get onForegroundMessage => fgCtrl.stream;

  @override
  Stream<IncomingBankingPushPayload> get onMessageOpenedApp => openCtrl.stream;

  @override
  Future<IncomingBankingPushPayload?> getInitialTerminatedMessage() async =>
      coldStart;

  Future<void> dispose() async {
    await regCtrl.close();
    await fgCtrl.close();
    await openCtrl.close();
  }
}

class _StubVoiceAdapter implements SpeechEngineAdapter {
  @override
  VoiceEngineId get engineId => VoiceEngineId.androidSpeech;

  @override
  bool get isStrictlyOffline => false;

  @override
  bool get supportsStreamingPartials => true;

  @override
  Future<EngineAvailabilityCheck> checkAvailability({
    required String locale,
  }) async => const EngineAvailabilityCheck(
    engineId: VoiceEngineId.androidSpeech,
    isAvailable: true,
    supportsVietnamese: true,
    serviceVersion: 'stub',
  );

  @override
  Future<EngineStartOutcome> startSession({
    required String sessionId,
    required int attemptId,
    required String ownerId,
    required String locale,
    required bool strictOffline,
  }) async => const EngineStartOutcome.success();

  @override
  Future<void> stopSession({
    required String sessionId,
    required int attemptId,
  }) async {}

  @override
  Future<void> cancelSession({
    required String sessionId,
    required int attemptId,
  }) async {}

  @override
  Stream<VoiceEnvelopeEvent> get events =>
      const Stream<VoiceEnvelopeEvent>.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VAULT-01: Unique Physical Files & Reference-Counted Deletion', () {
    test(
      'Uploading identical filename & content twice creates TWO distinct physical files; deleting doc 1 preserves doc 2',
      () async {
        final tempRoot = Directory.systemTemp.createTempSync('vault01_dup_');
        addTearDown(() {
          if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
        });

        final bridge = NativeSecureVaultBridge.testable();
        final storage = SparkSafeFileStorageService(
          customVaultRootPath: tempRoot.path,
          vaultBridge: bridge,
        );

        final bytes = Uint8List.fromList(utf8.encode('IDENTICAL_CONTRACT_PDF'));
        final expectedSha = sha256.convert(bytes).toString();

        final res1 = await storage.uploadUserAttachment(
          userId: 'u_vault01',
          folder: 'bills_contracts',
          fileName: 'contract.pdf',
          mimeType: 'application/pdf',
          bytes: bytes,
        );
        final res2 = await storage.uploadUserAttachment(
          userId: 'u_vault01',
          folder: 'bills_contracts',
          fileName: 'contract.pdf',
          mimeType: 'application/pdf',
          bytes: bytes,
        );

        final ref1 = (res1 as Success<StoredFileReference>).value;
        final ref2 = (res2 as Success<StoredFileReference>).value;

        expect(ref1.attachmentId, isNot(equals(ref2.attachmentId)));
        expect(ref1.storageKey, '${ref1.attachmentId}.enc');
        expect(ref2.storageKey, '${ref2.attachmentId}.enc');
        expect(ref1.localFilePath, isNot(equals(ref2.localFilePath)));

        final userDir = Directory(
          '${tempRoot.path}${Platform.pathSeparator}u_vault01',
        );
        final meta1 = File(
          '${userDir.path}${Platform.pathSeparator}${ref1.attachmentId}.meta.json',
        );
        final meta2 = File(
          '${userDir.path}${Platform.pathSeparator}${ref2.attachmentId}.meta.json',
        );
        expect(File(ref1.localFilePath!).existsSync(), isTrue);
        expect(File(ref2.localFilePath!).existsSync(), isTrue);
        expect(meta1.existsSync(), isTrue);
        expect(meta2.existsSync(), isTrue);

        // Delete doc 1 -> doc 1 physical + meta gone, doc 2 intact & readable
        final deleted1 = await storage.deleteAttachmentForUser(
          userId: 'u_vault01',
          attachmentId: ref1.attachmentId,
        );
        expect(deleted1, isTrue);
        expect(File(ref1.localFilePath!).existsSync(), isFalse);
        expect(meta1.existsSync(), isFalse);
        expect(File(ref2.localFilePath!).existsSync(), isTrue);
        expect(meta2.existsSync(), isTrue);

        final read2 = await storage.readLocalAttachmentBytes(
          userId: 'u_vault01',
          attachmentId: ref2.attachmentId,
          expectedPlaintextSha256: expectedSha,
        );
        final plain2 = (read2 as Success<Uint8List?>).value!;
        expect(sha256.convert(plain2).toString(), expectedSha);
        expect(plain2, equals(bytes));
      },
    );

    test(
      'Legacy shared physical file is only unlinked when attachment_index.json reference count drops to 0',
      () async {
        final tempRoot = Directory.systemTemp.createTempSync('vault01_refcnt_');
        addTearDown(() {
          if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
        });

        final bridge = NativeSecureVaultBridge.testable();
        final storage = SparkSafeFileStorageService(
          customVaultRootPath: tempRoot.path,
          vaultBridge: bridge,
        );

        final userDir = Directory(
          '${tempRoot.path}${Platform.pathSeparator}u_legacy_ref',
        )..createSync(recursive: true);
        const sharedKey = 'shared_legacy_doc.enc';
        final sharedPlain = Uint8List.fromList(utf8.encode('SHARED_LEGACY'));
        final sharedCipher = await bridge.encryptBytes(
          plainBytes: sharedPlain,
          aad: 'u_legacy_ref|$sharedKey',
        );
        final sharedFile = File(
          '${userDir.path}${Platform.pathSeparator}$sharedKey',
        )..writeAsBytesSync(sharedCipher, flush: true);
        final sharedMeta = File('${sharedFile.path}.meta')
          ..writeAsStringSync(
            jsonEncode({
              'ownerId': 'u_legacy_ref',
              'plaintextSha256': sha256.convert(sharedPlain).toString(),
              'encryptedSizeBytes': sharedCipher.lengthInBytes,
            }),
          );
        File(
          '${userDir.path}${Platform.pathSeparator}attachment_index.json',
        ).writeAsStringSync(
          jsonEncode({'att_legacy_1': sharedKey, 'att_legacy_2': sharedKey}),
        );

        // Delete first reference -> physical file MUST stay alive for att_legacy_2!
        expect(
          await storage.deleteAttachmentForUser(
            userId: 'u_legacy_ref',
            attachmentId: 'att_legacy_1',
          ),
          isTrue,
        );
        expect(sharedFile.existsSync(), isTrue);
        expect(sharedMeta.existsSync(), isTrue);

        final readSecond = await storage.readLocalAttachmentBytes(
          userId: 'u_legacy_ref',
          attachmentId: 'att_legacy_2',
        );
        expect((readSecond as Success<Uint8List?>).value, equals(sharedPlain));

        // Delete second (final) reference -> physical file & meta are now unlinked!
        expect(
          await storage.deleteAttachmentForUser(
            userId: 'u_legacy_ref',
            attachmentId: 'att_legacy_2',
          ),
          isTrue,
        );
        expect(sharedFile.existsSync(), isFalse);
        expect(sharedMeta.existsSync(), isFalse);
      },
    );
  });

  group('VAULT-02: Atomic Mutex-Serialized Index & Corruption Recovery', () {
    test(
      '20 concurrent uploads/deletes preserve all mappings and corrupted index recovers from .bak / *.meta.json',
      () async {
        final tempRoot = Directory.systemTemp.createTempSync('vault02_conc_');
        addTearDown(() {
          if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
        });

        final bridge = NativeSecureVaultBridge.testable();
        final storage = SparkSafeFileStorageService(
          customVaultRootPath: tempRoot.path,
          vaultBridge: bridge,
        );
        const uid = 'u_concurrent_vault';

        // 20 concurrent uploads
        final uploadResults = await Future.wait(
          List.generate(20, (i) {
            final payload = Uint8List.fromList(utf8.encode('DOC_PAYLOAD_$i'));
            return storage.uploadUserAttachment(
              userId: uid,
              folder: 'important_docs',
              fileName: 'file_$i.pdf',
              mimeType: 'application/pdf',
              bytes: payload,
            );
          }),
        );
        final refs = uploadResults
            .map((r) => (r as Success<StoredFileReference>).value)
            .toList();
        expect(refs.length, 20);

        final userDir = Directory(
          '${tempRoot.path}${Platform.pathSeparator}$uid',
        );
        final indexFile = File(
          '${userDir.path}${Platform.pathSeparator}attachment_index.json',
        );
        final bakFile = File(
          '${userDir.path}${Platform.pathSeparator}attachment_index.json.bak',
        );
        expect(indexFile.existsSync(), isTrue);
        expect(bakFile.existsSync(), isTrue);

        final mapAfter20 =
            jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
        expect(mapAfter20.length, 20);

        // Concurrently delete first 5 while uploading 5 more
        final deleteFutures = refs
            .take(5)
            .map(
              (ref) => storage.deleteAttachmentForUser(
                userId: uid,
                attachmentId: ref.attachmentId,
              ),
            );
        final extraUploadFutures = List.generate(5, (i) {
          final payload = Uint8List.fromList(utf8.encode('EXTRA_DOC_$i'));
          return storage.uploadUserAttachment(
            userId: uid,
            folder: 'important_docs',
            fileName: 'extra_$i.pdf',
            mimeType: 'application/pdf',
            bytes: payload,
          );
        });

        await Future.wait([...deleteFutures, ...extraUploadFutures]);
        final remainingRefs = refs.skip(5).toList();

        // Now corrupt/truncate attachment_index.json AND verify recovery via .bak + *.meta.json!
        indexFile.writeAsStringSync('{"att_truncated":', flush: true);

        for (var i = 0; i < remainingRefs.length; i++) {
          final ref = remainingRefs[i];
          final read = await storage.readLocalAttachmentBytes(
            userId: uid,
            attachmentId: ref.attachmentId,
            expectedPlaintextSha256: ref.plaintextSha256,
          );
          expect(
            utf8.decode((read as Success<Uint8List?>).value!),
            'DOC_PAYLOAD_${i + 5}',
          );
        }

        // Also delete BOTH attachment_index.json AND .bak -> rebuild strictly from *.meta.json!
        indexFile.writeAsStringSync('CORRUPT_NOT_JSON', flush: true);
        if (bakFile.existsSync()) bakFile.deleteSync();

        for (var i = 0; i < remainingRefs.length; i++) {
          final ref = remainingRefs[i];
          final read = await storage.readLocalAttachmentBytes(
            userId: uid,
            attachmentId: ref.attachmentId,
            expectedPlaintextSha256: ref.plaintextSha256,
          );
          expect(
            utf8.decode((read as Success<Uint8List?>).value!),
            'DOC_PAYLOAD_${i + 5}',
          );
        }

        final rebuiltMap =
            jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
        expect(rebuiltMap.length, 20); // 15 remaining + 5 extra
      },
    );
  });

  group('VAULT-03: Truthful Local Cleanup Queue & Retry', () {
    test(
      'Failed local delete persists pending_cleanups.json, exposes LocalCleanupPendingFailure, and retry clears it',
      () async {
        final tempRoot = Directory.systemTemp.createTempSync('vault03_queue_');
        addTearDown(() {
          if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
        });

        final db = FakeFirebaseFirestore();
        final failingStorage = _FailingThenRecoveringFileStorage()
          ..shouldReturnFalseOnDelete = true;

        final repo = DocumentVaultRepositoryImpl(
          db,
          fileStorage: failingStorage,
          customVaultRootPath: tempRoot.path,
        );

        final doc = DocumentVaultEntity(
          id: 'doc_q1',
          ownerId: 'u_q1',
          isFamilyShared: false,
          folder: DocumentFolderCategory.importantDocs,
          title: 'Hợp đồng mật',
          referenceCode: 'HD-99',
          note: '',
          uploadedByName: 'An',
          createdAt: DateTime(2026, 11, 27),
          storageLifecycle: DocumentStorageLifecycle.localDeviceOnlyBinary,
          attachmentId: 'att_fail_delete_01',
        );
        await db
            .collection('users')
            .doc('u_q1')
            .collection('documents')
            .doc(doc.id)
            .set({'id': doc.id, 'title': doc.title});

        final res = await repo.deleteDocument(userId: 'u_q1', document: doc);
        // Must NEVER falsely claim clean success when local file deletion failed!
        expect(res, isA<Err<void>>());
        final failure = (res as Err<void>).failure;
        expect(
          DocumentCleanupFailureCodes.isPendingLocalCleanup(failure),
          isTrue,
        );
        expect(failure.code, DocumentCleanupFailureCodes.pendingLocalCleanup);

        final pendingFile = File(
          '${tempRoot.path}${Platform.pathSeparator}u_q1${Platform.pathSeparator}pending_cleanups.json',
        );
        expect(pendingFile.existsSync(), isTrue);
        final rawQueue = jsonDecode(pendingFile.readAsStringSync()) as List;
        expect(rawQueue.length, 1);
        expect((rawQueue.single as Map)['attachmentId'], 'att_fail_delete_01');
        expect((rawQueue.single as Map)['timestamp'], isNotEmpty);
        expect(await repo.hasPendingLocalCleanups('u_q1'), isTrue);

        // Allow local deletion to succeed and run retry helper
        failingStorage.shouldReturnFalseOnDelete = false;
        final remaining = await repo.retryPendingLocalCleanups('u_q1');
        expect(remaining, 0);
        expect(await repo.hasPendingLocalCleanups('u_q1'), isFalse);
        expect(pendingFile.existsSync(), isFalse);
        expect(failingStorage.deletedAttachmentIds, ['att_fail_delete_01']);
      },
    );
  });

  group('VAULT-04: Fail-Closed Native Android SecureVault Read', () {
    test(
      'Native Android readSecret returning null or KEY_INVALIDATED clears stale _memoryFallback and returns null',
      () async {
        const channel = MethodChannel('vn.lifeos.app/secure_vault');
        String? mockNativeValue = 'native_secret_v1';
        String? mockErrorCode;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'writeSecret') return true;
              if (call.method == 'readSecret') {
                final errCode = mockErrorCode;
                if (errCode != null) {
                  throw PlatformException(
                    code: errCode,
                    message: 'Hardware keystore key permanently invalidated',
                  );
                }
                return mockNativeValue;
              }
              return true;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final bridge = NativeSecureVaultBridge.testable(
          forceNativeAndroidOverride: true,
        );
        // Host VM is not Android, so persistent hardware flag reflects actual OS
        expect(
          bridge.isPersistentHardwareStorageSupported,
          !kIsWeb && Platform.isAndroid,
        );

        await bridge.writeSecret(
          key: 'sepay_tok_u1',
          value: 'native_secret_v1',
        );
        expect(bridge.debugHasMemoryCacheEntry('sepay_tok_u1'), isTrue);
        expect(await bridge.readSecret('sepay_tok_u1'), 'native_secret_v1');

        // 1. Native returns null -> MUST purge stale _memoryFallback and return null!
        mockNativeValue = null;
        expect(await bridge.readSecret('sepay_tok_u1'), isNull);
        expect(bridge.debugHasMemoryCacheEntry('sepay_tok_u1'), isFalse);

        // 2. Seed RAM cache artificially + trigger KEY_INVALIDATED PlatformException -> fail-closed
        bridge.debugSeedMemoryFallback('sepay_tok_u1', 'stale_ram_leak');
        mockErrorCode = 'KEY_INVALIDATED';
        final outcome = await bridge.readSecretOutcome('sepay_tok_u1');
        expect(outcome.value, isNull);
        expect(outcome.status, VaultReadStatus.keyInvalidated);
        expect(outcome.isKeyInvalidated, isTrue);
        expect(bridge.lastReadWasKeyInvalidated, isTrue);
        expect(bridge.debugHasMemoryCacheEntry('sepay_tok_u1'), isFalse);

        // 3. Session reset wipes RAM cache cleanly
        bridge.debugSeedMemoryFallback('other_cached_key', 'secret');
        bridge.clearMemoryFallbackOnSessionReset();
        expect(bridge.debugHasMemoryCacheEntry('other_cached_key'), isFalse);
      },
    );
  });

  group(
    'ALARM-01: Serialized Epoch Switches, Namespaced IDs & Legacy Quarantine',
    () {
      setUp(() async {
        PersonalAlarmStore.instance.resetScopingForTest();
        NativeAlarmSchedulerBridge.instance.resetDebugCounters();
        await NativeAlarmSchedulerBridge.instance.clearAllAlarms();
        await NativeSecureVaultBridge.instance.clearAllSecrets();
      });

      tearDown(() async {
        PersonalAlarmStore.instance.resetScopingForTest();
        await NativeAlarmSchedulerBridge.instance.clearAllAlarms();
        await NativeSecureVaultBridge.instance.clearAllSecrets();
      });

      test(
        'Rapid A -> B -> A switches in < 100ms preserve active user A OS alarms and quarantine legacy alarms safely',
        () async {
          final store = PersonalAlarmStore.instance;
          final vault = NativeSecureVaultBridge.instance;

          // Pre-seed legacy unscoped alarms
          await vault.writeSecret(
            key: 'lifeos_personal_alarms_v1',
            value: jsonEncode([
              const PersonalAlarmItem(
                id: 'palarm_legacy_keep',
                hour: 5,
                minute: 30,
                label: 'Legacy Morning',
              ).toJson(),
            ]),
          );

          // Seed User A and User B alarms
          store.setActiveUserId('user_a');
          final alarmA = await store.upsertAlarm(
            hour: 6,
            minute: 30,
            label: 'Alarm User A',
            nowOverride: DateTime(2026, 11, 27, 5, 0),
          );
          store.setActiveUserId('user_b');
          final alarmB = await store.upsertAlarm(
            hour: 8,
            minute: 0,
            label: 'Alarm User B',
            nowOverride: DateTime(2026, 11, 27, 5, 0),
          );
          await store.flushPendingOperations();

          // Rapid A -> B -> A switches synchronously in < 10ms
          store.setActiveUserId('user_a');
          store.setActiveUserId('user_b');
          store.setActiveUserId('user_a');
          await store.flushPendingOperations();

          expect(store.activeUserId, 'user_a');
          final osAlarms = await NativeAlarmSchedulerBridge.instance
              .listScheduledAlarms();
          final expectedOsIdA = PersonalAlarmStore.osAlarmIdFor(
            'user_a',
            alarmA.id,
          );
          final expectedOsIdB = PersonalAlarmStore.osAlarmIdFor(
            'user_b',
            alarmB.id,
          );

          expect(expectedOsIdA, startsWith('palarm_user_a_'));
          expect(osAlarms.map((e) => e.eventId), contains(expectedOsIdA));
          expect(
            osAlarms.map((e) => e.eventId),
            isNot(contains(expectedOsIdB)),
          );

          // Legacy key was moved non-destructively to quarantine (NOT destroyed!)
          expect(await vault.readSecret('lifeos_personal_alarms_v1'), isNull);
          final quarantined = await store.loadQuarantinedLegacyAlarms();
          expect(quarantined.map((e) => e.id), ['palarm_legacy_keep']);

          // User explicitly imports quarantined alarms into active account A
          final afterImport = await store
              .importQuarantinedLegacyAlarmsForActiveUser(
                nowOverride: DateTime(2026, 11, 27, 5, 0),
              );
          expect(
            afterImport.map((e) => e.id),
            containsAll(['palarm_legacy_keep', alarmA.id]),
          );
          expect(await store.loadQuarantinedLegacyAlarms(), isEmpty);
        },
      );
    },
  );

  group('AI-01: Truthful Offline ASR Status (No Fake Installed Placeholders)', () {
    tearDown(() async {
      await sl.reset();
    });

    testWidgets(
      'Placeholder catalog has verifiedInferenceCapable == false, hasVerifiedInstalledAsrModel() == false, and VoiceDiagnosticsPage renders truthful unavailable badge',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final spec in LocalAsrModelCatalog.defaults) {
          expect(spec.runtimeIntegrated, isFalse);
          expect(spec.verifiedInferenceCapable, isFalse);
        }

        final tempDir = Directory.systemTemp.createTempSync('ai01_truth_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final modelRepo = LocalAsrModelManager(
          rootDirectory: tempDir,
          httpClient: MockClient((_) async => http.Response('', 404)),
        );
        expect(await modelRepo.hasVerifiedInstalledAsrModel(), isFalse);

        final coordinator = VoiceSessionCoordinator(
          engineRegistry: SpeechEngineRegistry(<SpeechEngineAdapter>[
            _StubVoiceAdapter(),
          ]),
          capabilityRepository: VoiceCapabilityRepositoryImpl(
            store: InMemoryVoiceCapabilityStore(),
          ),
          modelRepository: modelRepo,
          clock: FakeMonotonicClock(),
        );
        sl.registerSingleton<VoiceNativeChannelDataSource>(
          VoiceNativeChannelDataSource(),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => LifeOsTopToastHost(child: child!),
            home: BlocProvider<VoiceAssistantBloc>(
              create: (_) => VoiceAssistantBloc(
                coordinator: coordinator,
                modelRepository: modelRepo,
                disposeCoordinatorOnClose: true,
              ),
              child: const VoiceDiagnosticsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Chưa tích hợp bộ chạy offline (Dùng Android trên máy hoặc nhập tay)',
          ),
          findsNWidgets(LocalAsrModelCatalog.defaults.length),
        );
        expect(find.text('✓ Đã tải sẵn & Kích hoạt'), findsNothing);
      },
    );
  });

  group('CAL-01: Chunked Batch Delete (<=400) & Idempotent 404 Handling', () {
    test(
      'Deleting a calendar with 550 events commits in <=400 op batches and treats Google HTTP 404 as idempotent success',
      () async {
        final fakeDb = FakeFirebaseFirestore();
        final spyDb = _SpyBatchFirestore(fakeDb);
        final googleApi404 = _Throwing404GoogleCalendarApi(statusToThrow: 404);
        final remote = CalendarRemoteDataSource(spyDb, googleApi: googleApi404);

        const cal = ManagedCalendarEntity(
          id: 'cal_big_550',
          ownerId: 'u_cal_big',
          summary: 'Lịch 550 sự kiện',
          colorHex: '#0B7A2A',
          googleCalendarId: 'gcal_550@group.calendar.google.com',
        );
        await fakeDb
            .collection('users')
            .doc('u_cal_big')
            .collection('calendars')
            .doc(cal.id)
            .set({'id': cal.id, 'summary': cal.summary});

        for (var i = 0; i < 550; i++) {
          await fakeDb
              .collection('users')
              .doc('u_cal_big')
              .collection('private_events')
              .doc('ev_$i')
              .set({
                'id': 'ev_$i',
                'ownerId': 'u_cal_big',
                'calendarId': cal.id,
                'title': 'Sự kiện $i',
              });
        }

        await remote.deleteCalendar(userId: 'u_cal_big', calendar: cal);

        expect(googleApi404.deleteCalled, isTrue);
        // 550 events + 1 calendar doc = 551 deletes -> chunks of 400 and 151!
        expect(spyDb.committedBatchSizes, [400, 151]);
        expect(spyDb.committedBatchSizes.every((n) => n <= 400), isTrue);

        final calSnap = await fakeDb
            .collection('users')
            .doc('u_cal_big')
            .collection('calendars')
            .doc(cal.id)
            .get();
        expect(calSnap.exists, isFalse);

        final remainingEvents = await fakeDb
            .collection('users')
            .doc('u_cal_big')
            .collection('private_events')
            .where('calendarId', isEqualTo: cal.id)
            .get();
        expect(remainingEvents.docs, isEmpty);
      },
    );

    test(
      'disconnectCalendarLocally removes local calendar & events without touching remote Google Calendar',
      () async {
        final fakeDb = FakeFirebaseFirestore();
        final googleApi = _Throwing404GoogleCalendarApi(statusToThrow: 500);
        final repo = CalendarRepositoryImpl(
          CalendarRemoteDataSource(fakeDb, googleApi: googleApi),
        );
        const cal = ManagedCalendarEntity(
          id: 'cal_local_dc',
          ownerId: 'u_cal_dc',
          summary: 'Lịch ngắt cục bộ',
          colorHex: '#0B7A2A',
          googleCalendarId: 'gcal_keep_remote',
        );
        await fakeDb
            .collection('users')
            .doc('u_cal_dc')
            .collection('calendars')
            .doc(cal.id)
            .set({'id': cal.id, 'summary': cal.summary});

        final res = await repo.disconnectCalendarLocally(
          userId: 'u_cal_dc',
          calendar: cal,
        );
        expect(res, isA<Success<void>>());
        expect(googleApi.deleteCalled, isFalse);
      },
    );
  });

  group('BANK-06: FCM Audience Binding, Session Generation & Logout Order', () {
    test(
      'Drops FCM message targeting user_a when user_b is active and deactivates Firestore token BEFORE unregistering',
      () async {
        final db = FakeFirebaseFirestore();
        final driver = _SequencedFcmDriver(tokenToEmit: 'tok_user_b_1');
        addTearDown(driver.dispose);

        final fcm = FcmBankingMessagingService(firestore: db, driver: driver);
        final receivedFg = <IncomingBankingPushPayload>[];
        final receivedDl = <IncomingBankingPushPayload>[];
        final sub1 = fcm.foregroundNotifications.listen(receivedFg.add);
        final sub2 = fcm.deepLinkRequests.listen(receivedDl.add);
        addTearDown(sub1.cancel);
        addTearDown(sub2.cancel);

        // Verify mapDataMap extracts targetUid / ownerId
        final mappedFromTarget =
            FirebaseFcmPlatformDriver.mapDataMap(<String, dynamic>{
              'type': 'bank_transaction',
              'transactionId': 'tx_1',
              'targetUid': 'user_a',
            }, openedFromSystemTray: false)!;
        expect(mappedFromTarget.targetUid, 'user_a');

        final mappedFromOwner = FirebaseFcmPlatformDriver.mapDataMap(
          <String, dynamic>{
            'type': 'bank_transaction',
            'transactionId': 'tx_2',
            'ownerId': 'user_a',
          },
          openedFromSystemTray: true,
        )!;
        expect(mappedFromOwner.targetUid, 'user_a');

        await fcm.bindAuthenticatedUser('user_b');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Incoming message targeting user_a MUST be dropped when user_b is active!
        driver.fgCtrl.add(mappedFromTarget);
        driver.openCtrl.add(mappedFromOwner);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(receivedFg, isEmpty);
        expect(receivedDl, isEmpty);

        // Incoming message targeting user_b succeeds
        driver.fgCtrl.add(
          const IncomingBankingPushPayload(
            notificationId: 'n_b_1',
            transactionId: 'tx_b_1',
            walletId: 'w_b',
            connectionId: 'c_b',
            direction: 'credit',
            verificationStatus: 'VERIFIED',
            title: 'Biến động',
            body: '+100.000đ',
            openedFromSystemTray: false,
            targetUid: 'user_b',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(receivedFg.length, 1);
        expect(receivedFg.single.transactionId, 'tx_b_1');

        // Verify unbind deactivates Firestore token BEFORE unregisterDevice()!
        final devId = FcmBankingMessagingService.computeDeterministicDeviceId(
          'tok_user_b_1',
        );
        var sawPushDisabledBeforeUnregister = false;
        driver.events.clear();

        await fcm.unbindAndDeactivateOnLogout();
        final devDoc = await db
            .collection('users')
            .doc('user_b')
            .collection('devices')
            .doc(devId)
            .get();
        sawPushDisabledBeforeUnregister =
            devDoc.data()?['pushEnabled'] == false;
        expect(sawPushDisabledBeforeUnregister, isTrue);
        expect(driver.events, contains('unregisterDevice'));
      },
    );
  });

  group('PRIV-01: Explicit Cloud AI Consent, PII Minimization & Web Deletion SLA', () {
    test(
      'GeminiRemoteDataSource enforces explicit cloudAiConsentGranted and strips habit labels & PII when maskSensitiveInfo is true',
      () async {
        final vault = NativeSecureVaultBridge.testable();
        var httpCalls = 0;
        String? capturedBody;
        final mockHttp = MockClient((req) async {
          httpCalls += 1;
          capturedBody = req.body;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {
                          'text': jsonEncode({
                            'assistantInsightVi': 'Ổn định.',
                            'transactions': [],
                          }),
                        },
                      ],
                    },
                  },
                ],
              }),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final ds = GeminiRemoteDataSource(
          httpClient: mockHttp,
          vault: vault,
          initialUserId: 'u_priv_1',
        );

        // 1. Saving API key WITHOUT explicit consent keeps enabled=false & consent=false
        final keyOnlyCfg = await ds.writeConfig(
          userId: 'u_priv_1',
          newApiKey: 'AIzaSyTestPrivKey12345',
        );
        expect(keyOnlyCfg.enabled, isFalse);
        expect(ds.cloudAiConsentGranted, isFalse);

        // 2. Attempting cloud call without consent fails closed with 0 HTTP calls
        await expectLater(
          () => ds.generateMultiDomainPlan(
            userId: 'u_priv_1',
            rawInput: 'Tư vấn chi tiêu giúp tôi?',
            config: keyOnlyCfg.copyWith(enabled: true),
            referenceNow: DateTime(2026, 11, 27, 10, 0),
          ),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              'GEMINI_CONSENT_REQUIRED',
            ),
          ),
        );
        expect(httpCalls, 0);

        // 3. Granting explicit consent enables cloud call AND minimizes PII + habit titles
        final consentedCfg = await ds.writeConfig(
          userId: 'u_priv_1',
          cloudAiConsentGranted: true,
          enabled: true,
          maskSensitiveInfo: true,
        );
        expect(consentedCfg.enabled, isTrue);
        expect(ds.cloudAiConsentGranted, isTrue);

        const snapshot = GeminiContextSnapshot(
          monthlyIncomeMinor: 25000000,
          monthlyExpenseMinor: 10000000,
          safeDailyAllowanceMinor: 350000,
          upcomingEventsCount: 2,
          openTasksCount: 3,
          topHabitLabels: <String>[
            'Trả nợ anh Minh 0912345678',
            'Khám bệnh mật tại BV X',
          ],
        );

        final result = await ds.generateMultiDomainPlan(
          userId: 'u_priv_1',
          rawInput:
              'Chuyển 500k cho email user@secret.vn số 0987654321 STK 19036888999012',
          config: consentedCfg,
          referenceNow: DateTime(2026, 11, 27, 10, 0),
          contextSnapshot: snapshot,
        );

        expect(httpCalls, 1);
        expect(capturedBody, isNotNull);
        expect(capturedBody, isNot(contains('user@secret.vn')));
        expect(capturedBody, isNot(contains('0987654321')));
        expect(capturedBody, isNot(contains('19036888999012')));
        expect(capturedBody, isNot(contains('Trả nợ anh Minh')));
        expect(capturedBody, isNot(contains('Khám bệnh mật')));
        expect(result.sanitizedPrompt, contains('[ẨN_EMAIL]'));
        expect(result.sanitizedPrompt, contains('[ẨN_SĐT]'));
        expect(result.sanitizedPrompt, contains('[ẨN_SỐ_TK]'));

        // 4. Web deletion page transparently discloses instant in-app path & 7-day email SLA
        final html = File('web/delete-account.html').readAsStringSync();
        expect(html, contains('Hồ sơ &amp; Bảo mật Tài khoản'));
        expect(html, contains('Xóa tài khoản'));
        expect(html, contains('support@lifeos.vn'));
        expect(html, contains('7 ngày làm việc'));
      },
    );
  });
}
