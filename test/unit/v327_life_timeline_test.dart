import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/widgets/lifeos_design_system.dart';
import 'package:life_os/features/dashboard/domain/services/life_timeline_engine.dart';
import 'package:life_os/features/dashboard/presentation/pages/life_timeline_page.dart';

void main() {
  group('LifeTimelineEngine & LifeTimelinePage (Phase 16 — Section 20)', () {
    test(
      'deduplicates cross-module entries, sorts chronologically, filters by domain and folds Vietnamese accents',
      () {
        final now = DateTime(2026, 11, 25, 14, 0);
        final entries = <LifeTimelineEntry>[
          LifeTimelineEntry(
            dedupKey: 'finance:tx_1',
            sourceId: 'tx_1',
            domain: LifeTimelineDomain.finance,
            timestamp: now.subtract(const Duration(hours: 2)),
            title: 'Đổ xăng Honda Vision',
            subtitle: 'Di chuyển · Vietcombank',
            amountMinor: 70000,
            isCredit: false,
            badgeLabel: 'Chi tiêu',
            targetRoute: '/finance',
          ),
          // Duplicate key should be ignored cleanly
          LifeTimelineEntry(
            dedupKey: 'finance:tx_1',
            sourceId: 'tx_1',
            domain: LifeTimelineDomain.finance,
            timestamp: now.subtract(const Duration(hours: 2)),
            title: 'Đổ xăng Honda Vision (duplicate)',
            subtitle: 'Di chuyển',
            amountMinor: 70000,
            isCredit: false,
            badgeLabel: 'Chi tiêu',
            targetRoute: '/finance',
          ),
          LifeTimelineEntry(
            dedupKey: 'calendar:ev_1',
            sourceId: 'ev_1',
            domain: LifeTimelineDomain.calendar,
            timestamp: now.add(const Duration(hours: 3)),
            title: 'Họp tổng kết tháng',
            subtitle: 'Phòng họp A',
            badgeLabel: 'Sắp diễn ra',
            targetRoute: '/planning',
            isUpcoming: true,
          ),
          LifeTimelineEntry(
            dedupKey: 'family:sp_1',
            sourceId: 'sp_1',
            domain: LifeTimelineDomain.family,
            timestamp: now.subtract(const Duration(days: 1, hours: 1)),
            title: 'Ăn lẩu gia đình',
            subtitle: 'Chia nhóm 4 người',
            amountMinor: 600000,
            isCredit: false,
            badgeLabel: 'Chia tiền',
            targetRoute: '/family',
          ),
        ];

        final merged = LifeTimelineEngine.mergeAndFilter(rawEntries: entries);
        expect(merged.length, 3);
        expect(merged.first.sourceId, 'ev_1');
        expect(merged.last.sourceId, 'sp_1');

        // Accent-insensitive Vietnamese search
        final searched = LifeTimelineEngine.mergeAndFilter(
          rawEntries: entries,
          query: 'do xang vision',
        );
        expect(searched.length, 1);
        expect(searched.first.sourceId, 'tx_1');

        // Domain filter
        final onlyFamily = LifeTimelineEngine.mergeAndFilter(
          rawEntries: entries,
          domainFilter: LifeTimelineDomain.family,
        );
        expect(onlyFamily.length, 1);
        expect(onlyFamily.first.sourceId, 'sp_1');

        // Day grouping labels
        final groups = LifeTimelineEngine.groupByDay(merged, referenceNow: now);
        expect(groups.length, 2);
        expect(groups.first.labelVi, 'Hôm nay');
        expect(groups.last.labelVi, 'Hôm qua');
      },
    );

    testWidgets(
      'LifeTimelinePage renders cleanly at 360x800 @ 112% and supports live filter + search',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final now = DateTime.now();
        final sample = <LifeTimelineEntry>[
          LifeTimelineEntry(
            dedupKey: 'finance:tx_a',
            sourceId: 'tx_a',
            domain: LifeTimelineDomain.finance,
            timestamp: now,
            title: 'Nhận lương tháng 11',
            subtitle: 'Thu nhập · VCB',
            amountMinor: 15000000,
            isCredit: true,
            badgeLabel: 'Thu nhập',
            targetRoute: '/finance',
          ),
          LifeTimelineEntry(
            dedupKey: 'calendar:ev_a',
            sourceId: 'ev_a',
            domain: LifeTimelineDomain.calendar,
            timestamp: now.add(const Duration(hours: 2)),
            title: 'Nhắc bảo dưỡng xe máy',
            subtitle: 'Honda Head',
            badgeLabel: 'Sắp diễn ra',
            targetRoute: '/planning',
            isUpcoming: true,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(
                ctx,
              ).copyWith(textScaler: const TextScaler.linear(1.12)),
              child: LifeOsTopToastHost(child: child!),
            ),
            home: LifeTimelinePage(injectedEntries: sample),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Dòng thời gian Cuộc sống'), findsOneWidget);
        expect(find.text('Nhận lương tháng 11'), findsOneWidget);
        expect(find.text('Nhắc bảo dưỡng xe máy'), findsOneWidget);

        await tester.tap(find.byKey(const Key('timeline_filter_finance')));
        await tester.pumpAndSettle();
        expect(find.text('Nhận lương tháng 11'), findsOneWidget);
        expect(find.text('Nhắc bảo dưỡng xe máy'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
