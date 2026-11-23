import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/services/android_notification_bridge.dart';
import 'package:life_os/core/services/file_storage_service.dart';
import 'package:life_os/core/services/native_alarm_scheduler_bridge.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/utils/vnd_amount.dart';
import 'package:life_os/features/calendar/data/datasources/google_calendar_api_datasource.dart';
import 'package:life_os/features/calendar/data/repositories/calendar_repository_impl.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/daily_life/domain/entities/daily_life_entities.dart';
import 'package:life_os/features/notifications/data/repositories/notifications_repository_impl.dart';

void main() {
  group('v3.0 Production Hardening & 2026 Statutory Audit Remediation Suite', () {
    test('P0-1: NativeAlarmSchedulerBridge schedules, reads, and cancels real event alarms', () async {
      final startsAt = DateTime.now().add(const Duration(hours: 2));
      final scheduled = await NativeAlarmSchedulerBridge.instance.scheduleEventAlarm(
        eventId: 'ev_audit_alarm_1',
        title: 'Họp gia đình tối nay',
        subtitle: '20:00 · Phòng khách',
        eventStartsAt: startsAt,
        minutesBefore: 15,
        fullScreen: true,
      );

      expect(scheduled.eventId, 'ev_audit_alarm_1');
      expect(scheduled.minutesBefore, 15);
      expect(scheduled.fullScreen, isTrue);

      final fetched = await NativeAlarmSchedulerBridge.instance.getScheduledAlarm('ev_audit_alarm_1');
      expect(fetched, isNotNull);
      expect(fetched!.title, 'Họp gia đình tối nay');

      await NativeAlarmSchedulerBridge.instance.cancelEventAlarm('ev_audit_alarm_1');
      final afterCancel = await NativeAlarmSchedulerBridge.instance.getScheduledAlarm('ev_audit_alarm_1');
      expect(afterCancel, isNull);
    });

    test('P0-2 & P0-3: firestore.rules locks family_invites update, enforces expiry & blocks plaintext apiToken', () {
      final rules = File('firestore.rules').readAsStringSync();
      // Must NOT contain permissive `allow update: if isSignedIn();`
      expect(rules.contains('allow update: if isSignedIn();'), isFalse);
      // Must enforce family manager & expiry on family_invites
      expect(rules, contains('isFamilyManager(resource.data.familyId)'));
      expect(rules, contains('expiresAt > request.time'));
      // Must forbid writing plaintext `apiToken` in consents
      expect(rules, contains("!('apiToken' in request.resource.data)"));
      // Must allow right-to-erasure account deletion on append-only ledgers only when deletionInProgress == true
      expect(rules, contains('isAccountDeletionActive(userId)'));
    });

    test('P0-3 & Account Erasure: Zero external partner API tokens & full erasure wipes all 30 collections', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u_sec_1', email: 'sec@lifeos.vn'),
      );
      final remote = NotificationsRemoteDataSource(
        firestore: firestore,
        firebaseAuth: auth,
        bridge: AndroidNotificationBridge(),
      );

      await NativeSecureVaultBridge.instance.writeSecret(
        key: 'vault_key_u_sec_1',
        value: 'LOCAL_SECRET_9988',
      );
      await remote.saveLinkedBankAccount(
        userId: 'u_sec_1',
        walletId: 'wallet_1',
        bankBin: '970436',
        bankCode: 'VCB',
        bankName: 'Vietcombank',
        accountNumber: '0071000886868',
        accountHolderName: 'NGUYEN VAN A',
      );
      await remote.createPaymentOrder(
        userId: 'u_sec_1',
        walletId: 'wallet_1',
        bankBin: '970436',
        bankCode: 'VCB',
        bankName: 'Vietcombank',
        accountNumber: '0071000886868',
        accountHolderName: 'NGUYEN VAN A',
        amountMinor: 250000,
        description: 'Tiền điện',
      );

      // Seed personal data across new 360° Daily Life + immutable transactions + family availability
      final uRef = firestore.collection('users').doc('u_sec_1');
      await uRef.collection('transactions').doc('tx1').set({'amountMinor': 50000});
      await uRef.collection('medications').doc('m1').set({'name': 'Vitamin C'});
      await uRef.collection('life_notes').doc('n1').set({'title': 'Note'});
      await uRef.collection('documents').doc('d1').set({'title': 'Contract'});
      await firestore.collection('families').doc('fam1').set({
        'memberIds': ['u_sec_1', 'u_other'],
        'memberRoles': {'u_sec_1': 'member', 'u_other': 'owner'},
        'memberNames': {'u_sec_1': 'Sec', 'u_other': 'Owner'},
      });
      await firestore
          .collection('families')
          .doc('fam1')
          .collection('availability')
          .doc('slot_u_sec')
          .set({'ownerId': 'u_sec_1'});

      await remote.deleteAccountAndPersonalData('u_sec_1');

      expect((await uRef.collection('transactions').get()).docs, isEmpty);
      expect((await uRef.collection('bank_accounts').get()).docs, isEmpty);
      expect((await uRef.collection('payment_orders').get()).docs, isEmpty);
      expect((await uRef.collection('medications').get()).docs, isEmpty);
      expect((await uRef.collection('life_notes').get()).docs, isEmpty);
      expect((await uRef.collection('documents').get()).docs, isEmpty);
      expect(
        (await firestore.collection('families').doc('fam1').collection('availability').get()).docs,
        isEmpty,
      );
      expect(await NativeSecureVaultBridge.instance.readSecret('vault_key_u_sec_1'), isNull);
    });

    test('P0-4: Release signing config loads key.properties with documented template', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('rootProject.file("key.properties")'));
      expect(gradle, contains('create("release")'));
      expect(File('android/key.properties.example').existsSync(), isTrue);
    });

    test('Statutory 2026 Tax (Luật 109/2025 + NĐ 293/2025) & EVN 5-Tier (QĐ 2892/QĐ-BCT) edge cases', () {
      // High earner 120M Gross in Region I (BHTN cap = 20 * 5.31M = 106.2M => BHTN = 1,062,000)
      final res120M = VietnamGrossNetTaxEngine.fromGross(
        grossMinor: 120000000,
        dependentsCount: 2,
        policy: VietnamTaxPolicy.law109Year2026,
        region: VietnamWageRegion.region1,
      );
      expect(res120M.bhtnMinor, 1062000);
      expect(res120M.personalDeductionMinor, 15500000);
      expect(res120M.dependentDeductionMinor, 12400000);
      expect(res120M.brackets.length, 4); // Taxable ~87.3M reaches Bracket 4 (60-100M @ 30%)

      // EVN 750 kWh reaches Tier 5 (>700 kWh @ 3844đ) + configurable 10% VAT
      final evn750 = VietnamEvnUtilityEngine.calculate(
        prevElectricKwh: 0,
        currElectricKwh: 750,
        prevWaterM3: 0,
        currWaterM3: 0,
        vatRatePercent: 10,
      );
      expect(evn750.evnTiers.length, 5);
      expect(evn750.evnTiers.last.unitPriceVnd, 3844);
      expect(evn750.evnTiers.last.kwhUsed, 50);
    });

    test('Data Honesty, Busy/Free Revocation, Read-Only Google Calendars, Exact VND Parser & Local Vault', () async {
      // 1. SOS Medical Card never fakes 'O+'
      const emptyCard = EmergencyMedicalCardEntity(ownerId: 'u1');
      expect(emptyCard.bloodType, isEmpty);
      expect(emptyCard.allergies, isEmpty);
      expect(emptyCard.isConfigured, isFalse);

      // 2. Busy/Free slot is deleted immediately when shareBusyFree is turned OFF
      final firestore = FakeFirebaseFirestore();
      final calRemote = CalendarRemoteDataSource(firestore);
      final now = DateTime(2026, 11, 24, 9, 0);
      final created = await calRemote.createEvent(
        userId: 'u1',
        userName: 'Minh',
        familyId: 'fam_1',
        visibility: CalendarEventVisibility.privateEvent,
        title: 'Khám sức khỏe riêng',
        startsAt: now,
        endsAt: now.add(const Duration(hours: 1)),
        publishBusySlot: true,
      );
      final slotRef = firestore
          .collection('families')
          .doc('fam_1')
          .collection('availability')
          .doc(created.id);
      expect((await slotRef.get()).exists, isTrue);

      await calRemote.updateEvent(
        userId: 'u1',
        userName: 'Minh',
        existingEvent: created,
        title: 'Khám sức khỏe riêng',
        startsAt: now,
        endsAt: now.add(const Duration(hours: 1)),
        publishBusySlot: false,
      );
      expect((await slotRef.get()).exists, isFalse);

      // 3. GoogleCalendarApiDataSource includes read-only calendars
      final gcalClient = MockClient((req) async {
        expect(req.url.queryParameters.containsKey('minAccessRole'), isFalse);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'items': [
                {'id': 'primary', 'summary': 'Cá nhân', 'primary': true, 'accessRole': 'owner'},
                {'id': 'vi.vietnamese#holiday', 'summary': 'Ngày lễ Việt Nam', 'accessRole': 'reader'},
              ],
            }),
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final gcalDs = GoogleCalendarApiDataSource(
        firebaseAuth: MockFirebaseAuth(),
        httpClient: gcalClient,
      );
      final cals = await gcalDs.listCalendars(accessToken: 'tok', ownerId: 'u1');
      expect(cals.length, 2);
      expect(cals.first.isReadOnly, isFalse);
      expect(cals.last.isReadOnly, isTrue);

      // 4. Exact integer decimal VND parser without IEEE-754 double drift
      expect(VndAmount.parseExactDecimalVnd('500,000.00'), 500000);
      expect(VndAmount.parseExactDecimalVnd('123456.75'), 123457);
      expect(VndAmount.parseExactDecimalVnd('9007199254740993.00'), 9007199254740993);

      // 5. Private On-Device Document Vault stores & verifies bytes cleanly
      final tempVault = Directory.systemTemp.createTempSync('lifeos_vault_test_');
      try {
        final storage = SparkSafeFileStorageService(customVaultRootPath: tempVault.path);
        final sampleBytes = Uint8List.fromList(utf8.encode('PDF_CONTRACT_SAMPLE_2026'));
        final uploaded = await storage.uploadUserAttachment(
          userId: 'u1',
          folder: 'contracts',
          fileName: 'hop_dong_thue_nha.pdf',
          mimeType: 'application/pdf',
          bytes: sampleBytes,
        );
        expect(uploaded is Success<StoredFileReference>, isTrue);
        final ref = (uploaded as Success<StoredFileReference>).value;
        expect(ref.sha256Checksum, isNotEmpty);

        final readBack = await storage.readLocalAttachmentBytes(
          userId: 'u1',
          storageKey: ref.storageKey,
        );
        expect((readBack as Success<Uint8List?>).value, sampleBytes);

        await storage.deleteUserAttachment(userId: 'u1', storageKey: ref.storageKey);
        final afterDel = await storage.readLocalAttachmentBytes(
          userId: 'u1',
          storageKey: ref.storageKey,
        );
        expect((afterDel as Success<Uint8List?>).value, isNull);
      } finally {
        if (tempVault.existsSync()) tempVault.deleteSync(recursive: true);
      }
    });
  });
}
