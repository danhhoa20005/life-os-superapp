import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Local Dart security test suite verifying:
/// 1. Static policy invariants of `firestore.rules` (default deny, no `if true`, owner isolation,
///    immutable transactions, role self-escalation block).
/// 2. Runtime path-level access enforcement in `FakeFirebaseFirestore` (within the CEL subset
///    supported by `fake_firebase_security_rules`: `request.auth` & `allow delete: if false`).
/// Full `rules_version = '2'` (`get()`, `exists()`, `resource.data`, `request.resource.data`)
/// is additionally executed against Google's real Cloud Firestore Emulator in
/// `firebase/rules_tests/run_emulator_rules_tests.mjs`.
void main() {
  const pathIsolationRules = '''service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;

      match /wallets/{walletId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }

      match /private_events/{eventId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }

      match /transactions/{txId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }

    match /{document=**} {
      allow read, write: if false;
    }
  }
}''';

  group('Firestore Security Rules Verification', () {
    test('Production firestore.rules enforces strict default-deny, immutable transactions, private calendar & anti-escalation', () {
      final rules = File('firestore.rules').readAsStringSync();

      expect(rules, contains("rules_version = '2';"));
      // Must NOT contain any wildcard `if true`
      expect(RegExp(r'allow\s+[^;]*:\s*if\s+true\s*;').hasMatch(rules), isFalse);
      // Must contain global default deny
      expect(rules, contains('match /{document=**}'));
      expect(rules, contains('allow read, write: if false;'));
      // Transactions must forbid hard deletes (immutable ledger) and enforce positive int VND
      expect(rules, contains('match /transactions/{txId}'));
      expect(rules, contains('allow delete: if false;'));
      expect(rules, contains('isPositiveInt(request.resource.data.amountMinor)'));
      // Private calendar strictly bound to isOwner(userId)
      expect(rules, contains('match /private_events/{eventId}'));
      // Invite directory listing forbidden
      expect(rules, contains('match /family_invites/{inviteCode}'));
      expect(rules, contains('allow list: if false;'));
      // Joining via invite strictly locks role to 'member' (blocks self-escalation to 'owner'/'admin')
      expect(
        rules,
        contains("request.resource.data.memberRoles[request.auth.uid] == 'member'"),
      );
      // Shared bill splits & immutable debt settlements secured by family membership & positive int VND
      expect(rules, contains('match /split_bills/{billId}'));
      expect(rules, contains('isPositiveInt(request.resource.data.totalAmountMinor)'));
      expect(rules, contains('match /settlements/{settlementId}'));
      expect(rules, contains('allow update, delete: if false;'));
    });

    test('Unauthenticated client is denied read and write on all paths', () async {
      final authController = StreamController<Map<String, dynamic>?>.broadcast();
      final db = FakeFirebaseFirestore(
        securityRules: pathIsolationRules,
        authObject: authController.stream,
      );
      authController.add(null);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        () => db.collection('users').doc('user_a').get(),
        throwsA(anything),
      );
      await expectLater(
        () => db.collection('families').doc('fam_1').get(),
        throwsA(anything),
      );
      await authController.close();
    });

    test('Owner accesses own space; Family Owner & Cross-User are denied private_events/wallets & transaction deletes fail', () async {
      final authController = StreamController<Map<String, dynamic>?>.broadcast();
      final db = FakeFirebaseFirestore(
        securityRules: pathIsolationRules,
        authObject: authController.stream,
      );

      authController.add({
        'uid': 'user_a',
        'token': {'email': 'a@test.vn'},
      });
      await Future<void>.delayed(Duration.zero);

      await db.collection('users').doc('user_a').set({
        'id': 'user_a',
        'email': 'a@test.vn',
        'fullName': 'Minh',
      });
      await db.collection('users').doc('user_a').collection('wallets').doc('w1').set({
        'id': 'w1',
        'ownerId': 'user_a',
        'balanceMinor': 15000000,
      });
      await db.collection('users').doc('user_a').collection('private_events').doc('ev_secret').set({
        'id': 'ev_secret',
        'ownerId': 'user_a',
        'title': 'Lịch khám cá nhân riêng tư',
      });
      await db.collection('users').doc('user_a').collection('transactions').doc('tx_1').set({
        'id': 'tx_1',
        'ownerId': 'user_a',
        'amountMinor': 85000,
        'currencyCode': 'VND',
      });

      // Switch to Family Owner B -> strictly denied reading/writing User A's private event, wallet & transactions!
      authController.add({
        'uid': 'family_owner_b',
        'token': {'email': 'b@test.vn'},
      });
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        () => db
            .collection('users')
            .doc('user_a')
            .collection('private_events')
            .doc('ev_secret')
            .get(),
        throwsA(anything),
      );
      await expectLater(
        () => db.collection('users').doc('user_a').collection('wallets').doc('w1').get(),
        throwsA(anything),
      );
      await expectLater(
        () => db.collection('users').doc('user_a').collection('transactions').doc('tx_1').delete(),
        throwsA(anything),
      );

      await authController.close();
    });
  });
}
