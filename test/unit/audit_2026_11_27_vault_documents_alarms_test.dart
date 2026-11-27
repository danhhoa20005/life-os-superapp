import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/error/failure.dart';
import 'package:life_os/core/services/file_storage_service.dart';
import 'package:life_os/core/services/native_alarm_scheduler_bridge.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/services/personal_alarm_service.dart';
import 'package:life_os/features/authentication/domain/entities/user_entity.dart';
import 'package:life_os/features/authentication/domain/repositories/auth_repository.dart';
import 'package:life_os/features/authentication/domain/usecases/auth_usecases.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_bloc.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_event.dart';
import 'package:life_os/features/calendar/presentation/pages/event_detail_and_alarm_pages.dart';
import 'package:life_os/features/documents/data/repositories/document_vault_repository_impl.dart';
import 'package:life_os/features/documents/domain/entities/document_vault_entity.dart';
import 'package:life_os/features/documents/domain/repositories/document_vault_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

// ignore: subtype_of_sealed_class
class _MockFirestore extends Mock implements FirebaseFirestore {}

// ignore: subtype_of_sealed_class
class _MockCollectionRef extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockDocRef extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('H4: UID-Scoped Android Vault & Secret Cleanup', () {
    test(
      'NativeSecureVaultBridge.clearSecretsForUser removes ONLY target user keys and preserves other users + AEAD key',
      () async {
        final bridge = NativeSecureVaultBridge.testable();
        // Trigger creation of internal Dart AEAD master key slot
        final cipher = await bridge.encryptBytes(
          plainBytes: Uint8List.fromList(utf8.encode('probe_payload')),
          aad: 'probe',
        );

        await bridge.writeSecret(
          key: 'ux_last_used_wallet_id__u_userA',
          value: 'wallet_a',
        );
        await bridge.writeSecret(
          key: 'ux_form_draft_v1__u_userA__quick_tx_form',
          value: '{"amount":1000}',
        );
        await bridge.writeSecret(key: 'sepay_tok_userA', value: 'tok_secret_a');
        await bridge.writeSecret(key: 'userA_custom_pref', value: 'pref_a');
        await bridge.writeSecret(key: 'vault:userA:pin', value: '1234');

        // User B + prefix-similar userA0 + unscoped legacy key
        await bridge.writeSecret(
          key: 'ux_last_used_wallet_id__u_userB',
          value: 'wallet_b',
        );
        await bridge.writeSecret(
          key: 'ux_form_draft_v1__u_userA0__quick_tx_form',
          value: '{"amount":9999}',
        );
        await bridge.writeSecret(key: 'sepay_tok_userB', value: 'tok_secret_b');
        await bridge.writeSecret(
          key: 'global_unscoped_flag',
          value: 'keep_unscoped',
        );

        // Blank / traversal UIDs must safely no-op
        await bridge.clearSecretsForUser('');
        await bridge.clearSecretsForUser('   ');
        await bridge.clearSecretsForUser('.');
        await bridge.clearSecretsForUser('..');
        expect(
          await bridge.readSecret('ux_last_used_wallet_id__u_userA'),
          'wallet_a',
        );

        // Clear ONLY userA
        await bridge.clearSecretsForUser('userA');

        expect(
          await bridge.readSecret('ux_last_used_wallet_id__u_userA'),
          isNull,
        );
        expect(
          await bridge.readSecret('ux_form_draft_v1__u_userA__quick_tx_form'),
          isNull,
        );
        expect(await bridge.readSecret('sepay_tok_userA'), isNull);
        expect(await bridge.readSecret('userA_custom_pref'), isNull);
        expect(await bridge.readSecret('vault:userA:pin'), isNull);

        // User B, userA0, unscoped key, and AEAD master key MUST survive intact!
        expect(
          await bridge.readSecret('ux_last_used_wallet_id__u_userB'),
          'wallet_b',
        );
        expect(
          await bridge.readSecret('ux_form_draft_v1__u_userA0__quick_tx_form'),
          '{"amount":9999}',
        );
        expect(await bridge.readSecret('sepay_tok_userB'), 'tok_secret_b');
        expect(
          await bridge.readSecret('global_unscoped_flag'),
          'keep_unscoped',
        );
        final decrypted = await bridge.decryptBytes(
          cipherPack: cipher,
          aad: 'probe',
        );
        expect(utf8.decode(decrypted), 'probe_payload');
      },
    );

    test(
      'SparkSafeFileStorageService.clearVaultForUser deletes ONLY target user directory with containment verification',
      () async {
        final tempRoot = Directory.systemTemp.createTempSync('h4_vault_clear_');
        addTearDown(() {
          if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
        });

        final bridge = NativeSecureVaultBridge.testable();
        final storage = SparkSafeFileStorageService(
          customVaultRootPath: tempRoot.path,
          vaultBridge: bridge,
        );

        final resA = await storage.uploadUserAttachment(
          userId: 'user.alpha@lifeos.vn',
          folder: 'docs',
          fileName: 'a.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List.fromList(utf8.encode('ALPHA_DOC')),
        );
        final resB = await storage.uploadUserAttachment(
          userId: 'user.beta@lifeos.vn',
          folder: 'docs',
          fileName: 'b.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List.fromList(utf8.encode('BETA_DOC')),
        );
        final refA = (resA as Success<StoredFileReference>).value;
        final refB = (resB as Success<StoredFileReference>).value;

        expect(File(refA.localFilePath!).existsSync(), isTrue);
        expect(File(refB.localFilePath!).existsSync(), isTrue);

        // Invalid / blank userId must be a safe no-op
        await SparkSafeFileStorageService.clearVaultForUser(
          '',
          customVaultRootPath: tempRoot.path,
        );
        await SparkSafeFileStorageService.clearVaultForUser(
          '..',
          customVaultRootPath: tempRoot.path,
        );
        expect(File(refA.localFilePath!).existsSync(), isTrue);

        // Clear ONLY user Alpha
        await SparkSafeFileStorageService.clearVaultForUser(
          'user.alpha@lifeos.vn',
          customVaultRootPath: tempRoot.path,
        );

        final alphaDir = Directory(
          '${tempRoot.path}${Platform.pathSeparator}${SparkSafeFileStorageService.sanitizeUserIdSegment('user.alpha@lifeos.vn')}',
        );
        expect(alphaDir.existsSync(), isFalse);
        expect(File(refA.localFilePath!).existsSync(), isFalse);

        // Root & User Beta vault MUST stay 100% intact!
        expect(tempRoot.existsSync(), isTrue);
        expect(File(refB.localFilePath!).existsSync(), isTrue);
        final readB = await storage.readLocalAttachmentBytes(
          userId: 'user.beta@lifeos.vn',
          attachmentId: refB.attachmentId,
          expectedPlaintextSha256: refB.plaintextSha256,
        );
        expect(utf8.decode((readB as Success<Uint8List?>).value!), 'BETA_DOC');
      },
    );

    test(
      'Native Android LifeOsSecureVault.kt and MainActivity.kt implement UID-scoped clearForUser & clearUserSecrets',
      () {
        final vaultKt = File(
          'android/app/src/main/kotlin/vn/lifeos/app/life_os/LifeOsSecureVault.kt',
        ).readAsStringSync();
        expect(vaultKt, contains('fun sanitizeUserIdSegment('));
        expect(vaultKt, contains('fun clearForUser('));
        expect(vaultKt, contains('fun isUserScopedSecretKey('));

        // clearForUser must NEVER call prefs.edit().clear()
        final clearForUserBlock = vaultKt
            .split('fun clearForUser(')[1]
            .split('fun clearAll(')[0];
        expect(clearForUserBlock.contains('prefs.edit().clear()'), isFalse);

        final mainKt = File(
          'android/app/src/main/kotlin/vn/lifeos/app/life_os/MainActivity.kt',
        ).readAsStringSync();
        expect(mainKt, contains('"clearUserSecrets"'));
        expect(mainKt, contains('LifeOsSecureVault.clearForUser('));
      },
    );
  });

  group(
    'H6: Document Vault Path Traversal, Opaque attachmentId & Firestore-First Delete',
    () {
      test(
        'Syncs ONLY opaque attachmentId (no local paths) to Firestore & reads back via per-user attachment_index.json',
        () async {
          final tempRoot = Directory.systemTemp.createTempSync('h6_opaque_id_');
          addTearDown(() {
            if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
          });

          final bridge = NativeSecureVaultBridge.testable();
          final storage = SparkSafeFileStorageService(
            customVaultRootPath: tempRoot.path,
            vaultBridge: bridge,
          );
          final db = FakeFirebaseFirestore();
          final repo = DocumentVaultRepositoryImpl(db, fileStorage: storage);

          final created =
              (await repo.createDocument(
                        const CreateDocumentVaultParams(
                          userId: 'u_owner_a',
                          userName: 'An',
                          familyId: 'fam_1',
                          shareWithFamily: true,
                          folder: DocumentFolderCategory.importantDocs,
                          title: 'Hộ chiếu gia đình',
                          referenceCode: 'P1234567',
                        ),
                      )
                      as Success<DocumentVaultEntity>)
                  .value;

          final payloadBytes = Uint8List.fromList(
            utf8.encode('PASSPORT_BYTES_SECRET'),
          );
          final attached =
              (await repo.attachEncryptedLocalFile(
                        userId: 'u_owner_a',
                        document: created,
                        fileName: '../../evil/../../passport.png',
                        mimeType: 'image/png',
                        bytes: payloadBytes,
                      )
                      as Success<DocumentVaultEntity>)
                  .value;

          expect(
            SparkSafeFileStorageService.isValidAttachmentId(
              attached.attachmentId,
            ),
            isTrue,
          );
          expect(
            RegExp(r'^[A-Za-z0-9_-]{8,96}$').hasMatch(attached.attachmentId!),
            isTrue,
          );

          // Verify Firestore payload contains ONLY opaque attachmentId and NEVER raw paths!
          final snap = await db
              .collection('families')
              .doc('fam_1')
              .collection('documents')
              .doc(created.id)
              .get();
          final data = snap.data()!;
          expect(data['attachmentId'], attached.attachmentId);
          expect(data.containsKey('localAttachmentPath'), isFalse);
          expect(data.containsKey('localEncryptedPath'), isFalse);
          expect(data.containsKey('encryptedPath'), isFalse);
          expect(data.containsKey('localAttachmentStorageKey'), isFalse);

          // Verify per-user attachment_index.json exists inside <vaultRoot>/<sanitizedUserId>
          final indexFile = File(
            '${tempRoot.path}${Platform.pathSeparator}u_owner_a${Platform.pathSeparator}attachment_index.json',
          );
          expect(indexFile.existsSync(), isTrue);
          final indexMap =
              jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
          final mappedName = indexMap[attached.attachmentId] as String;
          expect(
            SparkSafeFileStorageService.isSingleSafeFileName(mappedName),
            isTrue,
          );
          expect(mappedName.contains('/'), isFalse);
          expect(mappedName.contains(r'\'), isFalse);
          expect(mappedName.contains('..'), isFalse);

          // Reload via watchDocuments (where localAttachmentPath is null) & decrypt via attachmentId
          final watched = await repo
              .watchDocuments(userId: 'u_owner_a', familyId: 'fam_1')
              .firstWhere((docs) => docs.isNotEmpty);
          expect(watched.single.localAttachmentPath, isNull);
          expect(watched.single.attachmentId, attached.attachmentId);

          final decrypted =
              (await repo.readEncryptedLocalFile(
                        userId: 'u_owner_a',
                        document: watched.single,
                      )
                      as Success<Uint8List?>)
                  .value;
          expect(decrypted, equals(payloadBytes));

          // Cross-user read of family shared doc must NOT touch u_owner_a's local vault
          final otherUserRead =
              (await repo.readEncryptedLocalFile(
                        userId: 'u_other_member',
                        document: watched.single,
                      )
                      as Success<Uint8List?>)
                  .value;
          expect(otherUserRead, isNull);
        },
      );

      test(
        'Canonical containment & deleteAttachmentForUser reject .. traversal, outside paths, and sibling vaults',
        () async {
          final tempRoot = Directory.systemTemp.createTempSync('h6_traversal_');
          addTearDown(() {
            if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
          });

          final bridge = NativeSecureVaultBridge.testable();
          final storage = SparkSafeFileStorageService(
            customVaultRootPath: tempRoot.path,
            vaultBridge: bridge,
          );

          final refUserB =
              (await storage.uploadUserAttachment(
                        userId: 'userB',
                        folder: 'docs',
                        fileName: 'victim_secret.enc',
                        mimeType: 'application/octet-stream',
                        bytes: Uint8List.fromList(utf8.encode('USER_B_SECRET')),
                      )
                      as Success<StoredFileReference>)
                  .value;
          final victimFile = File(refUserB.localFilePath!);
          final outsideFile = File(
            '${tempRoot.path}${Platform.pathSeparator}outside_system_file.txt',
          )..writeAsStringSync('DO_NOT_DELETE');

          // Ensure userA vault directory exists
          final refUserA =
              (await storage.uploadUserAttachment(
                        userId: 'userA',
                        folder: 'docs',
                        fileName: 'legit_a.enc',
                        mimeType: 'application/octet-stream',
                        bytes: Uint8List.fromList(utf8.encode('USER_A_DATA')),
                      )
                      as Success<StoredFileReference>)
                  .value;
          final userADir = Directory(
            '${tempRoot.path}${Platform.pathSeparator}userA',
          );

          // Traversal via .. into sibling userB vault
          final dotDotPath =
              '${userADir.path}${Platform.pathSeparator}..${Platform.pathSeparator}userB${Platform.pathSeparator}${refUserB.storageKey}';
          expect(
            SparkSafeFileStorageService.isCanonicalPathStrictlyInsideDirectory(
              userVaultDir: userADir,
              candidateFile: File(dotDotPath),
            ),
            isFalse,
          );
          expect(
            SparkSafeFileStorageService.isCanonicalPathStrictlyInsideDirectory(
              userVaultDir: userADir,
              candidateFile: File(
                '${userADir.path}${Platform.pathSeparator}nonexistent${Platform.pathSeparator}..${Platform.pathSeparator}..${Platform.pathSeparator}userB${Platform.pathSeparator}victim.enc',
              ),
            ),
            isFalse,
          );

          // deleteAttachmentForUser MUST reject all traversal / outside paths
          expect(
            await storage.deleteAttachmentForUser(
              userId: 'userA',
              legacyLocalPath: dotDotPath,
            ),
            isFalse,
          );
          expect(
            await storage.deleteAttachmentForUser(
              userId: 'userA',
              legacyLocalPath: victimFile.path,
            ),
            isFalse,
          );
          expect(
            await storage.deleteAttachmentForUser(
              userId: 'userA',
              legacyLocalPath: outsideFile.path,
            ),
            isFalse,
          );
          expect(
            await storage.deleteAttachmentForUser(
              userId: 'userA',
              attachmentId: '../userB/victim',
            ),
            isFalse,
          );
          expect(
            await storage.deleteAttachmentForUser(
              userId: 'userA',
              legacyLocalPath:
                  '${userADir.path}${Platform.pathSeparator}attachment_index.json',
            ),
            isFalse,
          );

          // Victim & outside & userA files remain intact
          expect(victimFile.existsSync(), isTrue);
          expect(outsideFile.existsSync(), isTrue);
          expect(File(refUserA.localFilePath!).existsSync(), isTrue);

          // Symlink escape check (when OS allows unprivileged symlink creation)
          final symlinkPath =
              '${userADir.path}${Platform.pathSeparator}evil_symlink.enc';
          var symlinkCreated = false;
          try {
            Link(symlinkPath).createSync(victimFile.path);
            symlinkCreated = true;
          } on FileSystemException {
            symlinkCreated = false;
          }
          if (symlinkCreated) {
            expect(
              SparkSafeFileStorageService.isCanonicalPathStrictlyInsideDirectory(
                userVaultDir: userADir,
                candidateFile: File(symlinkPath),
              ),
              isFalse,
            );
            expect(
              await storage.deleteAttachmentForUser(
                userId: 'userA',
                legacyLocalPath: symlinkPath,
              ),
              isFalse,
            );
            expect(victimFile.existsSync(), isTrue);
          }

          // Legacy file strictly INSIDE userA's vault directory CAN be deleted cleanly
          final legacyInsideFile = File(
            '${userADir.path}${Platform.pathSeparator}legacy_inside.enc',
          )..writeAsStringSync('LEGACY');
          final legacyInsideMeta = File('${legacyInsideFile.path}.meta')
            ..writeAsStringSync('{"ownerId":"userA"}');
          expect(
            await storage.deleteAttachmentForUser(
              userId: 'userA',
              legacyLocalPath: legacyInsideFile.path,
            ),
            isTrue,
          );
          expect(legacyInsideFile.existsSync(), isFalse);
          expect(legacyInsideMeta.existsSync(), isFalse);
        },
      );

      test(
        'deleteDocument executes Firestore delete FIRST and aborts without deleting local file on permission-denied',
        () async {
          final tempRoot = Directory.systemTemp.createTempSync('h6_fs_first_');
          addTearDown(() {
            if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
          });

          final bridge = NativeSecureVaultBridge.testable();
          final storage = SparkSafeFileStorageService(
            customVaultRootPath: tempRoot.path,
            vaultBridge: bridge,
          );

          final refA =
              (await storage.uploadUserAttachment(
                        userId: 'u_owner',
                        folder: 'bills_contracts',
                        fileName: 'contract.pdf',
                        mimeType: 'application/pdf',
                        bytes: Uint8List.fromList(utf8.encode('CONTRACT_DATA')),
                      )
                      as Success<StoredFileReference>)
                  .value;
          final encFile = File(refA.localFilePath!);
          expect(encFile.existsSync(), isTrue);

          final mockFs = _MockFirestore();
          final mockUsersCol = _MockCollectionRef();
          final mockUserDoc = _MockDocRef();
          final mockDocsCol = _MockCollectionRef();
          final mockTargetDoc = _MockDocRef();

          when(() => mockFs.collection('users')).thenReturn(mockUsersCol);
          when(() => mockUsersCol.doc('u_owner')).thenReturn(mockUserDoc);
          when(
            () => mockUserDoc.collection('documents'),
          ).thenReturn(mockDocsCol);
          when(() => mockDocsCol.doc('doc_1')).thenReturn(mockTargetDoc);
          when(() => mockTargetDoc.delete()).thenThrow(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
              message: 'Missing or insufficient permissions.',
            ),
          );

          final repo = DocumentVaultRepositoryImpl(
            mockFs,
            fileStorage: storage,
          );
          final doc = DocumentVaultEntity(
            id: 'doc_1',
            ownerId: 'u_owner',
            isFamilyShared: false,
            folder: DocumentFolderCategory.billsAndContracts,
            title: 'Hợp đồng',
            referenceCode: 'HD01',
            note: '',
            uploadedByName: 'An',
            createdAt: DateTime(2026, 11, 27),
            storageLifecycle: DocumentStorageLifecycle.localDeviceOnlyBinary,
            attachmentId: refA.attachmentId,
            localAttachmentPath: refA.localFilePath,
          );

          final res = await repo.deleteDocument(
            userId: 'u_owner',
            document: doc,
          );
          expect(res, isA<Err<void>>());
          expect((res as Err<void>).failure, isA<PermissionDeniedFailure>());
          // Local file MUST NOT have been deleted because Firestore threw permission-denied!
          expect(encFile.existsSync(), isTrue);
          expect(File('${encFile.path}.meta').existsSync(), isTrue);

          // Now allow Firestore delete to succeed -> local file IS deleted afterwards
          when(() => mockTargetDoc.delete()).thenAnswer((_) async {});
          final okRes = await repo.deleteDocument(
            userId: 'u_owner',
            document: doc,
          );
          expect(okRes, isA<Success<void>>());
          expect(encFile.existsSync(), isFalse);
          expect(File('${encFile.path}.meta').existsSync(), isFalse);
        },
      );
    },
  );

  group('M10: UID-Scoped Personal Alarm Isolation on Shared Devices', () {
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
      'Isolates alarms per UID, purges legacy unscoped key, blocks writes when signed out, and restores on re-login',
      () async {
        final store = PersonalAlarmStore.instance;
        final vault = NativeSecureVaultBridge.instance;

        // Pre-seed legacy unscoped alarm key from older version
        await vault.writeSecret(
          key: 'lifeos_personal_alarms_v1',
          value: jsonEncode([
            const PersonalAlarmItem(
              id: 'palarm_legacy',
              hour: 5,
              minute: 0,
              label: 'Legacy Alarm',
            ).toJson(),
          ]),
        );

        // 1. User A signs in -> legacy key purged, User A starts empty, creates alarm
        store.setActiveUserId('user_a');
        expect(await store.loadAlarms(), isEmpty);
        expect(await vault.readSecret('lifeos_personal_alarms_v1'), isNull);

        final alarmA = await store.upsertAlarm(
          hour: 6,
          minute: 30,
          label: 'Báo thức của A',
          repeatWeekdays: const [1, 2, 3, 4, 5],
        );
        expect((await store.loadAlarms()).map((e) => e.id), [alarmA.id]);
        expect(
          await vault.readSecret('lifeos_personal_alarms_v2__u_user_a'),
          isNotNull,
        );
        expect(
          await NativeAlarmSchedulerBridge.instance.getScheduledAlarm(
            alarmA.id,
          ),
          isNotNull,
        );

        // 2. User A signs out -> OS alarms canceled, loadAlarms returns [], writes blocked,
        //    AND User A's encrypted stored list remains preserved in vault!
        await store.clearSessionOnSignOut();
        expect(store.activeUserId, isNull);
        expect(await store.loadAlarms(), isEmpty);
        expect(
          await NativeAlarmSchedulerBridge.instance.listScheduledAlarms(),
          isEmpty,
        );
        expect(
          await vault.readSecret('lifeos_personal_alarms_v2__u_user_a'),
          isNotNull,
        );

        // Attempt writes while signed out -> ignored/blocked!
        await store.saveAlarms([
          const PersonalAlarmItem(
            id: 'palarm_unauth',
            hour: 9,
            minute: 0,
            label: 'Unauthorized',
          ),
        ]);
        await store.upsertAlarm(hour: 9, minute: 15, label: 'Blocked');
        expect(await store.loadAlarms(), isEmpty);
        expect(
          await NativeAlarmSchedulerBridge.instance.listScheduledAlarms(),
          isEmpty,
        );

        // 3. User B signs in -> sees ONLY empty list (never User A's alarm), creates User B alarm
        store.setActiveUserId('user_b');
        expect(await store.loadAlarms(), isEmpty);
        final alarmB = await store.upsertAlarm(
          hour: 8,
          minute: 0,
          label: 'Báo thức của B',
        );
        expect((await store.loadAlarms()).map((e) => e.label), [
          'Báo thức của B',
        ]);

        // 4. User B signs out and User A logs back in -> User A's alarms restored cleanly!
        await store.clearSessionOnSignOut();
        expect(
          await NativeAlarmSchedulerBridge.instance.listScheduledAlarms(),
          isEmpty,
        );

        store.setActiveUserId('user_a');
        // Allow async OS alarm resync microtask to run
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final restoredA = await store.loadAlarms();
        expect(restoredA.length, 1);
        expect(restoredA.single.id, alarmA.id);
        expect(restoredA.single.label, 'Báo thức của A');
        expect(
          await NativeAlarmSchedulerBridge.instance.getScheduledAlarm(
            alarmA.id,
          ),
          isNotNull,
        );
        expect(
          await NativeAlarmSchedulerBridge.instance.getScheduledAlarm(
            alarmB.id,
          ),
          isNull,
        );
      },
    );

    test(
      'AuthBloc binds PersonalAlarmStore on sign-in/restore and clears session on sign-out',
      () async {
        final mockRepo = _MockAuthRepository();
        final userA = UserEntity(
          id: 'u_auth_alarm_a',
          email: 'a@lifeos.vn',
          fullName: 'User A',
          emailVerified: true,
          timezone: 'Asia/Ho_Chi_Minh',
          onboardingCompleted: true,
          availabilityOptIn: false,
          createdAt: DateTime(2026, 11, 27),
        );
        when(
          () => mockRepo.watchCurrentUser(),
        ).thenAnswer((_) => Stream<UserEntity?>.value(userA));
        when(
          () => mockRepo.signOut(),
        ).thenAnswer((_) async => const Success(null));

        final bloc = AuthBloc(
          watchCurrentUser: WatchCurrentUserUseCase(mockRepo),
          signIn: SignInUseCase(mockRepo),
          signUp: SignUpUseCase(mockRepo),
          signInWithGoogle: SignInWithGoogleUseCase(mockRepo),
          linkGoogleAccount: LinkGoogleAccountUseCase(mockRepo),
          sendPasswordReset: SendPasswordResetUseCase(mockRepo),
          sendEmailVerification: SendEmailVerificationUseCase(mockRepo),
          reloadCurrentUser: ReloadCurrentUserUseCase(mockRepo),
          updateUserProfile: UpdateUserProfileUseCase(mockRepo),
          changePassword: ChangePasswordUseCase(mockRepo),
          completeOnboarding: CompleteOnboardingUseCase(mockRepo),
          updatePrivacySettings: UpdatePrivacySettingsUseCase(mockRepo),
          signOut: SignOutUseCase(mockRepo),
        );
        addTearDown(bloc.close);

        bloc.add(const AuthSubscriptionRequested());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(PersonalAlarmStore.instance.activeUserId, 'u_auth_alarm_a');

        await PersonalAlarmStore.instance.upsertAlarm(
          hour: 7,
          minute: 15,
          label: 'Auth A Alarm',
        );
        expect(
          (await PersonalAlarmStore.instance.loadAlarms()).single.label,
          'Auth A Alarm',
        );

        bloc.add(const AuthSignOutRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(PersonalAlarmStore.instance.activeUserId, isNull);
        expect(await PersonalAlarmStore.instance.loadAlarms(), isEmpty);
        expect(
          await NativeSecureVaultBridge.instance.readSecret(
            'lifeos_personal_alarms_v2__u_u_auth_alarm_a',
          ),
          isNotNull,
        );
      },
    );

    testWidgets(
      'EventAlarmPage scopes personal alarms by AuthBloc user and reloads cleanly on user switch',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('vn.lifeos.app/alarm_scheduler'),
              (call) async {
                if (call.method == 'listScheduledAlarms') return <dynamic>[];
                if (call.method == 'canScheduleExactAlarms') return true;
                return true;
              },
            );
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('vn.lifeos.app/alarm_scheduler'),
                null,
              );
        });

        await PersonalAlarmStore.instance.upsertAlarm(
          userId: 'u_page_a',
          hour: 6,
          minute: 45,
          label: 'Báo thức User A',
        );
        await PersonalAlarmStore.instance.upsertAlarm(
          userId: 'u_page_b',
          hour: 9,
          minute: 30,
          label: 'Báo thức User B',
        );

        final mockRepo = _MockAuthRepository();
        final userA = UserEntity(
          id: 'u_page_a',
          email: 'a@lifeos.vn',
          fullName: 'A',
          emailVerified: true,
          timezone: 'Asia/Ho_Chi_Minh',
          onboardingCompleted: true,
          availabilityOptIn: false,
          createdAt: DateTime(2026, 11, 27),
        );
        final userB = UserEntity(
          id: 'u_page_b',
          email: 'b@lifeos.vn',
          fullName: 'B',
          emailVerified: true,
          timezone: 'Asia/Ho_Chi_Minh',
          onboardingCompleted: true,
          availabilityOptIn: false,
          createdAt: DateTime(2026, 11, 27),
        );

        when(
          () => mockRepo.signIn(email: 'b@lifeos.vn', password: 'Password123!'),
        ).thenAnswer((_) async => Success(userB));
        when(
          () => mockRepo.signIn(email: 'a@lifeos.vn', password: 'Password123!'),
        ).thenAnswer((_) async => Success(userA));

        final authBloc = AuthBloc(
          watchCurrentUser: WatchCurrentUserUseCase(mockRepo),
          signIn: SignInUseCase(mockRepo),
          signUp: SignUpUseCase(mockRepo),
          signInWithGoogle: SignInWithGoogleUseCase(mockRepo),
          linkGoogleAccount: LinkGoogleAccountUseCase(mockRepo),
          sendPasswordReset: SendPasswordResetUseCase(mockRepo),
          sendEmailVerification: SendEmailVerificationUseCase(mockRepo),
          reloadCurrentUser: ReloadCurrentUserUseCase(mockRepo),
          updateUserProfile: UpdateUserProfileUseCase(mockRepo),
          changePassword: ChangePasswordUseCase(mockRepo),
          completeOnboarding: CompleteOnboardingUseCase(mockRepo),
          updatePrivacySettings: UpdatePrivacySettingsUseCase(mockRepo),
          signOut: SignOutUseCase(mockRepo),
        );

        authBloc.add(
          const AuthSignInSubmitted(
            email: 'a@lifeos.vn',
            password: 'Password123!',
          ),
        );
        await tester.pumpWidget(
          BlocProvider<AuthBloc>(
            create: (_) => authBloc,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const EventAlarmPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Báo thức User A'), findsWidgets);
        expect(find.textContaining('Báo thức User B'), findsNothing);

        // Switch authenticated account to User B -> EventAlarmPage reloads cleanly
        authBloc.add(
          const AuthSignInSubmitted(
            email: 'b@lifeos.vn',
            password: 'Password123!',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Báo thức User B'), findsWidgets);
        expect(find.textContaining('Báo thức User A'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
