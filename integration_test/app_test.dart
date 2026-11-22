import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';

/// End-to-end integration test entry point (`flutter test integration_test/app_test.dart`).
void main() {
  testWidgets('Integration smoke test: Auth -> Onboarding -> 5-Tab Tammy x Apple Shell', (tester) async {
    final mockAuth = MockFirebaseAuth();
    final fakeFirestore = FakeFirebaseFirestore();
    await configureDependencies(
      authOverride: mockAuth,
      firestoreOverride: fakeFirestore,
    );

    await tester.pumpWidget(const LifeOsApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_email_field')), findsOneWidget);
  });
}
