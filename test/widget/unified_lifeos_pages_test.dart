import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/features/authentication/presentation/pages/auth_pages.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/calendar/presentation/pages/event_detail_and_alarm_pages.dart';

void main() {
  test('Architectural Rule: Strictly ZERO Cubit classes anywhere in lib/', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in dartFiles) {
      final src = file.readAsStringSync();
      expect(
        RegExp(r'\bextends\s+Cubit\b').hasMatch(src),
        isFalse,
        reason: 'Forbidden Cubit found in ${file.path}',
      );
    }
  });

  testWidgets('WelcomePage and Full-Screen EventAlarmPage (07:30) render cleanly', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const WelcomePage(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Bắt đầu'), findsOneWidget);
    expect(find.text('Tôi đã có tài khoản'), findsOneWidget);

    final syncedEvent = CalendarEventEntity(
      id: 'gcal_real_standup',
      ownerId: 'uid_unified_test',
      ownerName: 'Nguyễn Hòa',
      visibility: CalendarEventVisibility.privateEvent,
      title: 'Họp dự án sáng thứ Hai',
      location: 'Google Meet',
      startsAt: DateTime(2026, 11, 23, 7, 45),
      endsAt: DateTime(2026, 11, 23, 8, 30),
      reminderMinutesBefore: 15,
      syncStatus: CalendarSyncStatus.synced,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: EventAlarmPage(event: syncedEvent),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Báo thức sự kiện'), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget);
    expect(find.text('Họp dự án sáng thứ Hai'), findsOneWidget);
    expect(find.text('Hoãn 5 phút'), findsOneWidget);
    expect(find.text('Tắt báo thức'), findsOneWidget);
  });

  testWidgets(
    'Unified LifeOS Navigation: Center + Quick Hub, Auto-Tx 98% Review, Document Vault & Settings Dark Mode',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockUser = MockUser(
        isAnonymous: false,
        uid: 'uid_unified_test',
        email: 'hoa@lifeos.vn',
        displayName: 'Nguyễn Hòa',
        isEmailVerified: true,
      );
      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
      final fakeFirestore = FakeFirebaseFirestore();
      await fakeFirestore.collection('users').doc('uid_unified_test').set({
        'id': 'uid_unified_test',
        'email': 'hoa@lifeos.vn',
        'fullName': 'Nguyễn Hòa',
        'onboardingCompleted': true,
        'availabilityOptIn': false,
        'createdAt': DateTime.now().toIso8601String(),
      });

      await configureDependencies(
        authOverride: mockAuth,
        firestoreOverride: fakeFirestore,
        httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
      );

      await tester.pumpWidget(const LifeOsApp());
      await tester.pumpAndSettle();

      // 1. Verify Unified Home Page (LifeOS wordmark, greeting, 3x3 Grid & Center + FAB)
      expect(find.text('LifeOS'), findsWidgets);
      expect(find.textContaining('Xin chào, Hòa'), findsOneWidget);
      expect(find.byKey(const Key('lifeos_center_quick_add_fab')), findsOneWidget);

      // 2. Open Redesigned Center + Quick Action Hub ("Thêm nhanh"):
      //    Verify 1-line instant expense save + 2×3 clear Bento tiles + Bank Review shortcut
      await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
      await tester.pumpAndSettle();
      expect(find.text('Thêm nhanh'), findsOneWidget);
      expect(find.text('Ghi thu chi'), findsOneWidget);
      expect(find.text('Chia tiền nhóm'), findsOneWidget);
      expect(find.text('Thêm lịch hẹn'), findsOneWidget);
      expect(find.text('Thêm việc làm'), findsOneWidget);
      expect(find.text('Mã QR thu tiền'), findsOneWidget);
      expect(find.text('Đi chợ & Ghi chú'), findsOneWidget);

      // Test 1-line instant input ("Cà phê 35k" -> Lưu) right inside `+` sheet!
      await tester.tap(find.text('Cà phê 35k'));
      await tester.pumpAndSettle();
      expect(find.textContaining('35.000 ₫'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quick_hub_save_inline_btn')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Re-open Center + Quick Action Hub -> Navigate to Auto-Transaction Review Page
      // When 0 pending bank transactions exist, verify honest Empty State (NO fake Circle K!)
      await tester.tap(find.byKey(const Key('lifeos_center_quick_add_fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick_hub_auto_tx_btn')));
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết giao dịch (Tự động)'), findsOneWidget);
      expect(find.text('Chưa có giao dịch tự động chờ duyệt'), findsOneWidget);
      expect(find.text('Circle K'), findsNothing);

      // Go back to Home & verify Live Omni-Search finds the "Cà phê" expense we just saved!
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tìm kiếm nhanh LifeOS').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('omni_search_text_field')), 'Cà phê');
      await tester.pumpAndSettle();
      expect(find.text('Cà phê'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('-35.000 ₫'),
        ),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byKey(const Key('omni_search_text_field')))).pop();
      await tester.pumpAndSettle();

      // 3. Scroll Home ListView into view and tap "Tài liệu" tile in Home 3x3 Grid
      await tester.drag(find.byType(ListView).first, const Offset(0, -320));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tài liệu'));
      await tester.pumpAndSettle();

      expect(find.text('Tài liệu gia đình'), findsOneWidget);
      expect(find.text('Hóa đơn & Hợp đồng'), findsOneWidget);
      expect(find.text('Giấy tờ xe'), findsOneWidget);

      await tester.drag(find.byType(ListView).first, const Offset(0, -250));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm tài liệu'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('document_title_input')),
        'Đăng ký xe Toyota Cross 30H-123.45',
      );
      await tester.tap(find.byKey(const Key('submit_document_button')));
      await tester.pumpAndSettle();

      expect(find.text('Đăng ký xe Toyota Cross 30H-123.45'), findsOneWidget);

      // Go back to Home and open Settings Hub ("Cài đặt")
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cài đặt'));
      await tester.pumpAndSettle();

      expect(find.text('Đồng bộ Google Calendar'), findsOneWidget);
      expect(find.text('Nhận diện thông báo ngân hàng'), findsOneWidget);
      expect(find.text('Chế độ tối'), findsOneWidget);

      // Toggle True Dark Mode live!
      await tester.drag(find.byType(ListView).first, const Offset(0, -250));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_dark_mode_switch')));
      await tester.pumpAndSettle();
      expect(find.text('Đang bật'), findsOneWidget);
    },
  );
}
