import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/backup/lifeos_backup_restore_engine.dart';
import 'package:life_os/core/offline/offline_outbox_service.dart';
import 'package:life_os/core/search/global_search_and_command_engine.dart';
import 'package:life_os/features/automation/domain/entities/automation_entities.dart';
import 'package:life_os/features/automation/domain/services/smart_automation_engine.dart';
import 'package:life_os/features/budgets/domain/services/cashflow_forecast_engine.dart';
import 'package:life_os/features/calendar/domain/services/daily_planner_timeblock_engine.dart';
import 'package:life_os/features/dashboard/domain/services/life_insights_engine.dart';
import 'package:life_os/features/notifications/domain/services/smart_inbox_engine.dart';
import 'package:life_os/features/pro_utilities/domain/services/receipt_intelligence_engine.dart';
import 'package:life_os/features/pro_utilities/domain/services/subscription_intelligence_engine.dart';
import 'package:life_os/features/vehicles/domain/services/vehicle_intelligence_engine.dart';

void main() {
  group('Part V & VII Product Expansion Engines — Full Verification Suite', () {
    test('Section 17: SmartInboxEngine deduplicates by source key, prioritizes critical items, and respects snooze', () {
      final now = DateTime(2026, 11, 25, 12, 0);
      final snap = SmartInboxEngine.build(
        referenceNow: now,
        rawCandidates: [
          SmartInboxItem(
            dedupKey: 'bank_provisional::tx_1',
            kind: SmartInboxKind.bankProvisional,
            priority: SmartInboxPriority.normal,
            titleVi: 'VCB -55.000 ₫ (cũ)',
            subtitleVi: 'Bản cũ',
            timestamp: now.subtract(const Duration(minutes: 10)),
            targetRoute: '/auto-tx-review',
            primaryActionLabelVi: 'Duyệt',
          ),
          SmartInboxItem(
            dedupKey: 'bank_provisional::tx_1',
            kind: SmartInboxKind.bankProvisional,
            priority: SmartInboxPriority.high,
            titleVi: 'VCB -55.000 ₫',
            subtitleVi: 'Chờ xác nhận',
            timestamp: now,
            targetRoute: '/auto-tx-review',
            primaryActionLabelVi: 'Duyệt',
          ),
          SmartInboxItem(
            dedupKey: 'doc_expiring::cccd_1',
            kind: SmartInboxKind.documentExpiring,
            priority: SmartInboxPriority.critical,
            titleVi: 'CCCD sắp hết hạn',
            subtitleVi: 'Còn 5 ngày',
            timestamp: now,
            targetRoute: '/family-documents',
            primaryActionLabelVi: 'Gia hạn',
          ),
          SmartInboxItem(
            dedupKey: 'med::m1',
            kind: SmartInboxKind.medicationReminder,
            priority: SmartInboxPriority.high,
            titleVi: 'Uống Vitamin C',
            subtitleVi: '13:00',
            timestamp: now,
            targetRoute: '/health-hub',
            primaryActionLabelVi: 'Đã uống',
            snoozedUntil: now.add(const Duration(hours: 1)),
          ),
        ],
      );

      expect(snap.activeItems.length, 2); // duplicate merged + 1 snoozed
      expect(snap.snoozedItems.length, 1);
      expect(snap.activeItems.first.dedupKey, 'doc_expiring::cccd_1');
      expect(snap.unreadActionableCount, 2);
    });

    test('Section 18: GlobalSearchAndCommandEngine handles unaccented/abbreviated queries and enforces strict cross-member privacy', () {
      const corpus = [
        SearchableEntityRecord(
          id: 'tx_cf_1',
          domain: SearchDomainKind.transaction,
          title: 'Cà phê muối Highlands',
          subtitle: '-45.000 ₫',
          targetRoute: '/finance',
          ownerUserId: 'user_a',
        ),
        SearchableEntityRecord(
          id: 'tx_secret_b',
          domain: SearchDomainKind.transaction,
          title: 'Cà phê bí mật của thành viên B',
          subtitle: '-90.000 ₫',
          targetRoute: '/finance',
          ownerUserId: 'user_b',
          familyId: 'fam_shared',
          isPrivateToOwner: true,
        ),
        SearchableEntityRecord(
          id: 'bill_shared',
          domain: SearchDomainKind.bill,
          title: 'Hóa đơn cà phê nhóm chung',
          subtitle: '240.000 ₫',
          targetRoute: '/family',
          ownerUserId: 'user_b',
          familyId: 'fam_shared',
          isPrivateToOwner: false,
        ),
      ];

      final hits = GlobalSearchAndCommandEngine.search(
        rawQuery: 'cf',
        activeUserId: 'user_a',
        corpus: corpus,
        allowedFamilyIds: const {'fam_shared'},
      );
      final ids = hits.map((h) => h.record.id).toList();
      expect(ids, contains('tx_cf_1'));
      expect(ids, contains('bill_shared'));
      // STRICT RBAC: user_b's private transaction MUST NEVER appear even in shared family!
      expect(ids, isNot(contains('tx_secret_b')));

      final cmdHits = GlobalSearchAndCommandEngine.search(
        rawQuery: 'mo quy gia dinh',
        activeUserId: 'user_a',
        corpus: corpus,
      );
      expect(cmdHits.first.record.id, 'cmd_open_family_fund');
    });

    test('Section 19: ReceiptIntelligenceEngine parses VAT/discount, flags total mismatch, and splits itemized shares to exact VND', () {
      const validReceipt = '''
Nhà hàng Lẩu Phố Quận 1
Bò Mỹ thượng hạng x2 320.000
Rau nấm tổng hợp 90.000
Cà phê sữa riêng Minh 40.000
Giảm giá thành viên -50.000
VAT 8% 32.000
Tổng thanh toán: 432.000đ
''';
      final parsed = ReceiptIntelligenceEngine.analyzeOcrText(validReceipt);
      expect(parsed.documentType, ReceiptDocumentType.restaurant);
      expect(parsed.items.length, 3);
      expect(parsed.itemsSubtotalMinor, 450000);
      expect(parsed.discountMinor, 50000);
      expect(parsed.vatMinor, 32000);
      expect(parsed.computedNetTotalMinor, 432000);
      expect(parsed.isTotalVerified, isTrue);
      expect(parsed.requiresManualTotalReview, isFalse);

      // Assign item 3 ("Cà phê sữa riêng Minh" 40k) to u_minh only
      final customized = StructuredReceiptAnalysis(
        documentType: parsed.documentType,
        merchantName: parsed.merchantName,
        items: [
          parsed.items[0],
          parsed.items[1],
          parsed.items[2].copyWith(assignedMemberIds: const ['u_minh']),
        ],
        itemsSubtotalMinor: parsed.itemsSubtotalMinor,
        vatMinor: parsed.vatMinor,
        surchargeMinor: parsed.surchargeMinor,
        discountMinor: parsed.discountMinor,
        statedTotalMinor: parsed.statedTotalMinor,
        computedNetTotalMinor: parsed.computedNetTotalMinor,
        discrepancyMinor: parsed.discrepancyMinor,
      );
      final shares = ReceiptIntelligenceEngine.computeItemizedGroupShares(
        analysis: customized,
        allParticipantIds: const ['u_hoa', 'u_minh', 'u_lan'],
      );
      expect(shares.values.fold<int>(0, (a, b) => a + b), 432000);
      expect(shares['u_minh']!, greaterThan(shares['u_hoa']!));

      // Mismatched OCR total MUST require manual review
      final bad = ReceiptIntelligenceEngine.analyzeOcrText(
        'Siêu thị Mini\nSữa tươi 50.000\nTổng thanh toán: 90.000đ',
      );
      expect(bad.isTotalVerified, isFalse);
      expect(bad.requiresManualTotalReview, isTrue);
    });

    test('Section 20: SmartAutomationEngine enforces loop guard, idempotency, and RBAC permission boundaries', () {
      final rules = SmartAutomationEngine.defaultRulesForUser('u_1');
      final salaryEvent = AutomationDomainEvent(
        eventId: 'ev_sal_11',
        triggerKind: AutomationTriggerKind.incomeSalaryReceived,
        actorUserId: 'u_1',
        occurredAt: DateTime(2026, 11, 25),
        amountMinor: 25000000,
        title: 'Lương tháng 11',
      );

      final firstRun = SmartAutomationEngine.evaluate(
        event: salaryEvent,
        rules: rules,
        activeUserId: 'u_1',
      );
      expect(firstRun.suggestions.length, 1);
      expect(
        firstRun.suggestions.first.actionKind,
        AutomationActionKind.suggestSalaryBudgetAllocation,
      );

      // Re-evaluating with same processed idempotency key skips duplicate
      final secondRun = SmartAutomationEngine.evaluate(
        event: salaryEvent,
        rules: rules,
        activeUserId: 'u_1',
        processedIdempotencyKeys: {firstRun.suggestions.first.idempotencyKey},
      );
      expect(secondRun.suggestions, isEmpty);
      expect(
        secondRun.audits.single.status,
        AutomationAuditStatus.skippedDuplicate,
      );

      // Event originated from automation MUST be blocked by loop guard
      final looped = SmartAutomationEngine.evaluate(
        event: AutomationDomainEvent(
          eventId: 'ev_loop_1',
          triggerKind: AutomationTriggerKind.incomeSalaryReceived,
          actorUserId: 'u_1',
          occurredAt: DateTime(2026, 11, 25),
          amountMinor: 25000000,
          title: 'Auto generated',
          originatedFromAutomation: true,
        ),
        rules: rules,
        activeUserId: 'u_1',
      );
      expect(looped.suggestions, isEmpty);
      expect(
        looped.audits.single.status,
        AutomationAuditStatus.blockedLoopGuard,
      );
    });

    test('Section 21: LifeOsBackupRestoreEngine encrypts/decrypts, blocks tampered archives, migrates v1, and guards replace mode', () {
      final archiveEncrypted = LifeOsBackupRestoreEngine.createBackupArchive(
        ownerId: 'u_old',
        passphrase: 'MatKhauAnToan#2026',
        collections: {
          'wallets': [
            {'id': 'w1', 'name': 'Ví chính', 'balanceMinor': 5000000},
          ],
          'transactions': [
            {
              'id': 'tx1',
              'merchant': 'Phở Hòa',
              'amountMinor': 55000,
              'occurredAt': '2026-11-25',
            },
          ],
        },
      );
      expect(archiveEncrypted.contains('Phở Hòa'), isFalse);

      // Wrong password must fail authentication tag check
      expect(
        () => LifeOsBackupRestoreEngine.previewAndValidateArchive(
          archiveEncrypted,
          passphrase: 'SaiMatKhau',
        ),
        throwsFormatException,
      );

      final preview = LifeOsBackupRestoreEngine.previewAndValidateArchive(
        archiveEncrypted,
        passphrase: 'MatKhauAnToan#2026',
      );
      expect(preview.summary.checksumVerified, isTrue);
      expect(preview.summary.wasEncrypted, isTrue);
      expect(preview.summary.transactionCount, 1);

      // Merge mode skips duplicates and preserves existing data
      final merged = LifeOsBackupRestoreEngine.applyRestorePlan(
        existingCollections: {
          'transactions': [
            {
              'id': 'tx1',
              'merchant': 'Phở Hòa',
              'amountMinor': 55000,
              'occurredAt': '2026-11-25',
            },
            {
              'id': 'tx_local',
              'merchant': 'Xăng xe',
              'amountMinor': 80000,
              'occurredAt': '2026-11-25',
            },
          ],
        },
        incomingCollections: preview.collections,
        targetUserId: 'u_new',
        mode: BackupRestoreMode.merge,
      );
      expect(merged.report.skippedDuplicateCount, 1);
      expect(merged.resultingCollections['transactions']!.length, 2);

      // Replace mode without explicit confirmation MUST throw StateError
      expect(
        () => LifeOsBackupRestoreEngine.applyRestorePlan(
          existingCollections: const {},
          incomingCollections: preview.collections,
          targetUserId: 'u_new',
          mode: BackupRestoreMode.replaceConfirmed,
          explicitReplaceConfirmation: false,
        ),
        throwsStateError,
      );
    });

    test('Section 22 & 23: LifeInsightsEngine & CashflowForecastEngine compute exact deterministic metrics', () {
      final insights = LifeInsightsEngine.compute(
        period: LifeInsightPeriodKind.monthly,
        incomeMinor: 25000000,
        expenseMinor: 15000000,
        previousPeriodExpenseMinor: 12500000,
        netWorthMinor: 120000000,
        totalDebtMinor: 10000000,
        fixedCostMinor: 7000000,
        currentCategorySpendMinor: const {'Ăn uống': 4600000},
        previousCategorySpendMinor: const {'Ăn uống': 4000000},
        completedTasksCount: 18,
        totalTasksCount: 20,
      );
      expect(insights.netSavingsMinor, 10000000);
      expect(insights.savingsRatePct, 40.0);
      expect(
        insights.observations.any(
          (o) => o.headlineVi.contains('Chi phí Ăn uống tháng này tăng 15% so với tháng trước.'),
        ),
        isTrue,
      );

      final forecast = CashflowForecastEngine.buildPlan(
        referenceDate: DateTime(2026, 11, 25),
        currentLiquidBalanceMinor: 12000000,
        emergencySavingsMinor: 40000000,
        baselineMonthlyIncomeMinor: 24000000,
        observedDailyVariableSpendMinor: 250000,
        scheduledItems: [
          ScheduledCashflowItem(
            id: 'rent',
            title: 'Tiền thuê nhà',
            amountMinor: 5000000,
            dueDate: DateTime(2026, 12, 1),
            cycleDays: 30,
          ),
        ],
        debts: const [
          DebtObligationItem(
            id: 'd_low',
            name: 'Vay người thân',
            balanceMinor: 5000000,
            annualInterestPct: 0.0,
            minimumMonthlyPaymentMinor: 500000,
          ),
          DebtObligationItem(
            id: 'd_high',
            name: 'Thẻ tín dụng',
            balanceMinor: 15000000,
            annualInterestPct: 24.0,
            minimumMonthlyPaymentMinor: 1500000,
          ),
        ],
      );
      expect(forecast.forecast7d.dailyBalancesMinor.length, 7);
      expect(forecast.forecast30d.dailyBalancesMinor.length, 30);
      expect(forecast.forecast90d.dailyBalancesMinor.length, 90);
      expect(forecast.avalanchePayoffOrder.first.id, 'd_high');
      expect(forecast.snowballPayoffOrder.first.id, 'd_low');
    });

    test('Section 24, 25, 26 & 36: Subscriptions, Vehicle TCO, Time-Blocking Redaction & Offline Outbox', () {
      // Section 24: Subscriptions
      final subs = SubscriptionIntelligenceEngine.analyze(
        referenceNow: DateTime(2026, 11, 25),
        services: [
          RecurringServiceInput(
            id: 'sub_nf',
            name: 'Netflix',
            currentAmountMinor: 260000,
            cycle: BillingRecurrenceCycle.monthly,
            nextBillingDate: DateTime(2026, 11, 27),
            priceHistory: [
              PriceHistoryPoint(
                recordedAt: DateTime(2026, 9, 1),
                amountMinor: 220000,
              ),
            ],
          ),
        ],
      );
      expect(subs.normalizedMonthlyTotalMinor, 260000);
      expect(subs.alerts.any((a) => a.kind == 'price_increase'), isTrue);

      // Section 25: Vehicle Intelligence (refuses unverified models, computes L/100km & ₫/km)
      expect(
        VehicleIntelligenceEngine.lookupVerifiedSpec(
          brand: 'Honda',
          modelName: 'Vision 110',
        ),
        isNotNull,
      );
      expect(
        VehicleIntelligenceEngine.lookupVerifiedSpec(
          brand: 'UnknownBrand',
          modelName: 'MysteryBike 999',
        ),
        isNull,
      );
      final vehStats = VehicleIntelligenceEngine.computeAnalytics(
        vehicleId: 'v1',
        fuelLogs: [
          FuelOrChargeLog(
            id: 'f1',
            vehicleId: 'v1',
            odometerKm: 10000,
            litersOrKwh: 4.0,
            costMinor: 95000,
            loggedAt: DateTime(2026, 11, 1),
          ),
          FuelOrChargeLog(
            id: 'f2',
            vehicleId: 'v1',
            odometerKm: 10200,
            litersOrKwh: 3.8,
            costMinor: 90000,
            loggedAt: DateTime(2026, 11, 11),
          ),
        ],
        maintenanceAndRepairMinor: 110000,
        insuranceAndInspectionMinor: 0,
        nextOilDueOdoKm: 12000,
      );
      expect(vehStats.trackedDistanceKm, 200);
      expect(vehStats.consumptionPer100Km, 1.9);
      expect(vehStats.costPerKmMinor, 1000); // (90k + 110k) / 200 km

      // Section 26: Daily Planner & Private Redaction
      final dayPlan = DailyPlannerTimeblockEngine.buildDayPlan(
        targetDay: DateTime(2026, 11, 25),
        viewerUserId: 'member_b',
        rawBlocks: [
          TimeBlockSlot(
            id: 'ev_priv',
            title: 'Khám sức khỏe cá nhân mật',
            description: 'Bệnh viện ĐHYD',
            startsAt: DateTime(2026, 11, 25, 9, 0),
            endsAt: DateTime(2026, 11, 25, 10, 30),
            ownerUserId: 'member_a',
            sharedWithFamily: false,
          ),
        ],
      );
      expect(dayPlan.timedBlocks.single.title, 'Khung giờ bận');
      expect(dayPlan.timedBlocks.single.description, isNull);
      final scheduledTask = DailyPlannerTimeblockEngine.scheduleTaskIntoFreeWindow(
        taskId: 't_report',
        taskTitle: 'Hoàn tất báo cáo quý',
        ownerUserId: 'member_b',
        dayPlan: dayPlan,
      );
      expect(scheduledTask, isNotNull);
      expect(scheduledTask!.linkedTaskId, 't_report');

      // Section 36: Offline Outbox Backoff
      expect(OfflineOutboxService.computeBackoffDelayMs(0), 1500);
      expect(OfflineOutboxService.computeBackoffDelayMs(2), 6000);
    });
  });
}
