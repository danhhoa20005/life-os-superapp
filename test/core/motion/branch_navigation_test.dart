import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';

void main() {
  group('Shell Navigation, Interruptibility, Scroll Preservation & Sheets (NAV-01..06, SHEET-01..02, CAL-01, TASK-01)', () {
    testWidgets(
      'NAV-01, NAV-02, NAV-03, NAV-04, NAV-06 & SHEET-01..02: Rapid mid-flight tab changes synchronize dock & body, preserve long Finance scroll, and handle sheet/detail interruption cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const uid = 'u_motion_nav';
        final db = FakeFirebaseFirestore();
        final now = DateTime.now();
        final monthKey =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

        await db.collection('users').doc(uid).set({
          'id': uid,
          'email': 'motion@lifeos.vn',
          'fullName': 'Nguyễn Minh',
          'onboardingCompleted': true,
        });
        await db
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_cash_default')
            .set({
              'id': 'wallet_cash_default',
              'ownerId': uid,
              'name': 'Tiền mặt',
              'type': 'cash',
              'balanceMinor': 15000000,
            });

        // Seed 28 transactions so Finance ledger is genuinely scrollable (NAV-03, TX-05)
        for (var i = 0; i < 28; i++) {
          await db
              .collection('users')
              .doc(uid)
              .collection('transactions')
              .doc('tx_seed_$i')
              .set({
                'id': 'tx_seed_$i',
                'ownerId': uid,
                'walletId': 'wallet_cash_default',
                'walletName': 'Tiền mặt',
                'categoryName': 'Ăn uống',
                'kind': 'expense',
                'direction': 'debit',
                'amountMinor': 45000 + (i * 1000),
                'currencyCode': 'VND',
                'merchant': 'Quán ăn số $i',
                'occurredAt': Timestamp.fromDate(
                  now.subtract(Duration(minutes: i * 5)),
                ),
                'monthKey': monthKey,
                'verification': 'userConfirmed',
              });
        }

        // Seed a personal task for TASK-01 completion + undo check
        await db
            .collection('users')
            .doc(uid)
            .collection('personal_tasks')
            .doc('task_motion_1')
            .set({
              'id': 'task_motion_1',
              'title': 'Kiểm tra sổ thu chi tối nay',
              'createdBy': uid,
              'creatorName': 'Nguyễn Minh',
              'assigneeId': uid,
              'assigneeName': 'Nguyễn Minh',
              'status': 'accepted',
              'priority': 'high',
              'recurrence': 'none',
              'dueAt': Timestamp.fromDate(now.add(const Duration(hours: 2))),
              'createdAt': Timestamp.fromDate(now),
            });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'motion@lifeos.vn',
            displayName: 'Nguyễn Minh',
          ),
        );
        await sl.reset();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: db,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
        );

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        // NAV-01: Verify Today tab initial state & sliding pill left-side position
        expect(find.byKey(const Key('lifeos_liquid_glass_bottom_dock')), findsOneWidget);
        final pillTab0 = tester.getRect(
          find.byKey(const Key('lifeos_sliding_dock_pill')),
        );

        // NAV-02: Rapid mid-flight tab changes (0 -> 2 -> 1 -> 3 separated by 40ms!)
        await tester.tap(find.text('Lịch & Việc').last);
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(find.text('Tài chính').last);
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(find.text('Gia đình').last);
        await tester.pumpAndSettle();

        // Final destination MUST be Family (tab 3) and dock pill MUST be on far right
        final pillTab3 = tester.getRect(
          find.byKey(const Key('lifeos_sliding_dock_pill')),
        );
        expect(pillTab3.left, greaterThan(pillTab0.left + 150));
        expect(find.byKey(const Key('open_create_space_button')), findsOneWidget);

        // NAV-03: Switch to Finance, scroll down > 320px, switch away to Planning, then return
        await tester.tap(find.text('Tài chính').last);
        await tester.pumpAndSettle();

        final txListFinder = find.byKey(const Key('transactions_list_view'));
        expect(txListFinder, findsOneWidget);
        await tester.drag(txListFinder, const Offset(0, -420));
        await tester.pumpAndSettle();

        final scrollableState = tester.state<ScrollableState>(
          find.descendant(of: txListFinder, matching: find.byType(Scrollable)).first,
        );
        final savedOffset = scrollableState.position.pixels;
        expect(savedOffset, greaterThan(250));

        // Switch to Lịch & Việc (CAL-01 & TASK-01)
        await tester.tap(find.text('Lịch & Việc').last);
        await tester.pumpAndSettle();

        // CAL-01: Rapidly switch calendar horizons (Ngày -> Tuần -> Tháng)
        await tester.tap(find.text('Tuần').first);
        await tester.pump(const Duration(milliseconds: 45));
        await tester.tap(find.text('Tháng').first);
        await tester.pumpAndSettle();

        // TASK-01: Switch to Công việc sub-tab, complete task, then undo back to active
        await tester.tap(find.byKey(const Key('planning_tasks_tab')));
        await tester.pumpAndSettle();
        final taskCheckbox = find.byKey(const Key('task_checkbox_task_motion_1'));
        expect(taskCheckbox, findsOneWidget);
        await tester.tap(taskCheckbox);
        await tester.pumpAndSettle();
        // Undo completion by tapping checkbox again
        await tester.tap(taskCheckbox);
        await tester.pumpAndSettle();

        // Return to Finance -> scroll offset MUST still equal savedOffset (NAV-03)!
        await tester.tap(find.text('Tài chính').last);
        await tester.pumpAndSettle();
        final restoredScrollable = tester.state<ScrollableState>(
          find.descendant(of: txListFinder, matching: find.byType(Scrollable)).first,
        );
        expect(restoredScrollable.position.pixels, closeTo(savedOffset, 1.0));

        // SHEET-01 & SHEET-02: Open Quick-Create sheet, simulate keyboard inset, dismiss, reopen
        await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('quick_hub_smart_input')), findsOneWidget);

        tester.view.viewInsets = const FakeViewPadding(left: 0, top: 0, right: 0, bottom: 280);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();

        // Dismiss Quick-Create sheet via close button and verify overlay is gone
        await tester.tap(find.byTooltip('Đóng'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('quick_hub_smart_input')), findsNothing);

        // NAV-04 & NAV-06: Push shared-axis detail route (`/financial-ai`) and pop mid-transition cleanly
        await tester.tap(find.byKey(const Key('open_financial_ai_assistant_btn')));
        await tester.pump(const Duration(milliseconds: 90));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('transactions_list_view')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
