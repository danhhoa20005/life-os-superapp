import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/widgets/backup_restore_studio_sheet.dart';
import 'package:life_os/core/widgets/lifeos_design_system.dart';
import 'package:life_os/features/automation/data/repositories/automation_repository_impl.dart';
import 'package:life_os/features/automation/presentation/bloc/automation_bloc.dart';
import 'package:life_os/features/automation/presentation/pages/automation_studio_page.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/calendar/presentation/widgets/daily_timeblock_planner_card.dart';
import 'package:life_os/features/pro_utilities/presentation/widgets/receipt_itemized_split_panel.dart';
import 'package:life_os/features/tasks/domain/entities/task_entities.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/presentation/widgets/cashflow_forecast_plan_card.dart';
import 'package:life_os/features/transactions/presentation/widgets/life_insights_cross_domain_card.dart';
import 'package:life_os/features/vehicles/domain/entities/vehicle_entities.dart';
import 'package:life_os/features/vehicles/presentation/widgets/vehicle_fuel_tco_card.dart';

Widget _wrapWithToastAndTheme(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    builder: (_, inner) => LifeOsTopToastHost(child: inner!),
    home: child,
  );
}

void main() {
  group('Part V–VI Product Expansion UI Flows Verification', () {
    testWidgets(
      'AutomationStudioPage loads 9 deterministic rules, toggles rule state & shows TopToast',
      (tester) async {
        final db = FakeFirebaseFirestore();
        final repo = AutomationRepositoryImpl(db);
        late final AutomationBloc bloc;

        await tester.pumpWidget(
          _wrapWithToastAndTheme(
            BlocProvider<AutomationBloc>(
              create: (_) =>
                  bloc = AutomationBloc(repository: repo)
                    ..add(const AutomationStarted('u_auto_ui')),
              child: const AutomationStudioPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tự động hóa Thông minh'), findsOneWidget);
        expect(find.textContaining('Đang bật 9/9 quy tắc'), findsOneWidget);

        // Toggle the first rule switch ('auto_salary_budget') without scrolling Hero card off-screen
        final firstSwitch = find.byKey(
          const Key('automation_rule_switch_auto_salary_budget'),
        );
        expect(firstSwitch, findsOneWidget);
        await tester.tap(firstSwitch);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(bloc.state.rules.first.enabled, isFalse);
        expect(find.textContaining('Đang bật 8/9 quy tắc'), findsOneWidget);
        expect(
          find.byKey(const Key('lifeos_top_toast_banner')),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'CashflowForecastPlanCard & LifeInsightsCrossDomainCard render 7/30/90d projections & verified insights cleanly on 360x800',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final wallets = <WalletEntity>[
          const WalletEntity(
            id: 'w1',
            ownerId: 'u1',
            name: 'VCB Lương',
            type: WalletType.bank,
            balanceMinor: 18000000,
          ),
          const WalletEntity(
            id: 'w2',
            ownerId: 'u1',
            name: 'Tiết kiệm Khẩn cấp',
            type: WalletType.savings,
            balanceMinor: 42000000,
          ),
        ];
        final now = DateTime(2026, 11, 15, 10);
        final txs = <TransactionEntity>[
          TransactionEntity(
            id: 'tx_inc',
            ownerId: 'u1',
            walletId: 'w1',
            categoryName: 'Lương',
            kind: TransactionKind.income,
            direction: 'credit',
            amountMinor: 25000000,
            merchant: 'Công ty ABC',
            occurredAt: now,
            monthKey: '2026-11',
            verification: TransactionVerification.verified,
            sourceKind: TransactionSourceKind.manual,
            crossSourceFingerprint: 'fp_inc_1',
          ),
          TransactionEntity(
            id: 'tx_exp',
            ownerId: 'u1',
            walletId: 'w1',
            categoryName: 'Ăn uống',
            kind: TransactionKind.expense,
            direction: 'debit',
            amountMinor: 6000000,
            merchant: 'Siêu thị',
            occurredAt: now,
            monthKey: '2026-11',
            verification: TransactionVerification.userConfirmed,
            sourceKind: TransactionSourceKind.manual,
            crossSourceFingerprint: 'fp_exp_1',
          ),
        ];

        await tester.pumpWidget(
          _wrapWithToastAndTheme(
            Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  CashflowForecastPlanCard(
                    wallets: wallets,
                    transactions: txs,
                    referenceDate: now,
                  ),
                  const SizedBox(height: 12),
                  const LifeInsightsCrossDomainCard(
                    periodCode: 'month',
                    incomeMinor: 25000000,
                    expenseMinor: 6000000,
                    expenseByCategory: {'Ăn uống': 6000000},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('cashflow_forecast_plan_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('life_insights_cross_domain_card')),
          findsOneWidget,
        );

        // Switch horizon to 90 ngày and open assumptions disclosure
        await tester.tap(find.text('90 ngày'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('cashflow_forecast_assumptions_toggle')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('forecast_income_delta_slider')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ReceiptItemizedSplitPanel verifies exact sum vs flags discrepancy when OCR total mismatches',
      (tester) async {
        const verifiedReceipt =
            'Siêu thị Co.opmart\nThịt bò 150.000\nRau xanh 50.000\nTổng cộng: 200.000đ';
        const mismatchedReceipt =
            'Nhà hàng Biển Đông\nLẩu hải sản 350.000\nNước suối 20.000\nTổng cộng: 500.000đ';

        await tester.pumpWidget(
          _wrapWithToastAndTheme(
            const Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    ReceiptItemizedSplitPanel(
                      rawOcrText: verifiedReceipt,
                      currentUserId: 'u1',
                      currentUserName: 'Hòa',
                    ),
                    ReceiptItemizedSplitPanel(
                      rawOcrText: mismatchedReceipt,
                      currentUserId: 'u1',
                      currentUserName: 'Hòa',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tổng tiền khớp từng món'), findsOneWidget);
        expect(find.textContaining('cần kiểm tra'), findsOneWidget);
      },
    );

    testWidgets(
      'Backup & Restore Sheet exports masked SHA-256 archive & validates restore preview',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          _wrapWithToastAndTheme(
            Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: FilledButton(
                    key: const Key('open_backup_sheet_btn'),
                    onPressed: () => showLifeOsBackupRestoreSheet(ctx),
                    child: const Text('Mở Sao lưu'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('open_backup_sheet_btn')));
        await tester.pumpAndSettle();

        expect(find.text('Sao lưu & Khôi phục Toàn vẹn'), findsOneWidget);

        // Export unencrypted SHA-256 archive -> raw JSON is masked by default!
        await tester.tap(find.byKey(const Key('backup_export_json_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('••••••••••••••••••••'), findsOneWidget);

        // Switch to Restore tab -> use recent archive -> verify SHA-256 badge
        await tester.tap(find.text('Khôi phục dữ liệu'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('backup_use_recent_archive_chip')),
        );
        await tester.pumpAndSettle();

        final sheetList = find.byKey(
          const Key('backup_restore_sheet_list_view'),
        );
        await tester.drag(sheetList, const Offset(0, -280));
        await tester.pumpAndSettle();

        expect(find.text('Khớp toàn vẹn SHA-256'), findsOneWidget);
        expect(
          find.byKey(const Key('backup_apply_restore_btn')),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(const Key('backup_apply_restore_btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('backup_apply_restore_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const Key('lifeos_top_toast_banner')),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'VehicleFuelAndTcoCard & DailyTimeblockPlannerCard display OEM reference & conflict badge',
      (tester) async {
        final vehicle = VehicleEntity(
          id: 'veh_vision_1',
          ownerId: 'u1',
          isFamilyShared: false,
          name: 'Honda Vision 110',
          plateNumber: '59X1-123.45',
          currentOdometerKm: 12000,
          lastServiceOdometerKm: 10500,
          serviceIntervalKm: 2000,
          lastServiceDate: DateTime(2026, 10, 1),
          serviceIntervalDays: 180,
          modelProfileKey: 'honda_esp_vision_110',
        );
        final day = DateTime(2026, 11, 25);
        final overlappingEvents = <CalendarEventEntity>[
          CalendarEventEntity(
            id: 'ev1',
            ownerId: 'u1',
            ownerName: 'Hòa',
            visibility: CalendarEventVisibility.privateEvent,
            title: 'Họp sáng',
            startsAt: DateTime(2026, 11, 25, 9, 0),
            endsAt: DateTime(2026, 11, 25, 10, 30),
          ),
          CalendarEventEntity(
            id: 'ev2',
            ownerId: 'u1',
            ownerName: 'Hòa',
            visibility: CalendarEventVisibility.privateEvent,
            title: 'Gặp khách hàng',
            startsAt: DateTime(2026, 11, 25, 10, 0),
            endsAt: DateTime(2026, 11, 25, 11, 0),
          ),
        ];
        final openTasks = <TaskEntity>[
          const TaskEntity(
            id: 't1',
            createdBy: 'u1',
            creatorName: 'Hòa',
            assigneeId: 'u1',
            assigneeName: 'Hòa',
            title: 'Soạn báo cáo quý',
            status: TaskWorkflowStatus.inProgress,
          ),
        ];

        await tester.pumpWidget(
          _wrapWithToastAndTheme(
            Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  VehicleFuelAndTcoCard(
                    vehicle: vehicle,
                    maintenanceCostMinor: 180000,
                  ),
                  const SizedBox(height: 12),
                  DailyTimeblockPlannerCard(
                    selectedDate: day,
                    userId: 'u1',
                    userName: 'Hòa',
                    dayEvents: overlappingEvents,
                    openTasks: openTasks,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('vehicle_fuel_and_tco_card')),
          findsOneWidget,
        );
        expect(find.textContaining('Honda Việt Nam'), findsOneWidget);
        expect(find.text('1 trùng giờ'), findsOneWidget);
      },
    );
  });
}
