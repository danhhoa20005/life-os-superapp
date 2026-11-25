import 'package:equatable/equatable.dart';

enum BillingRecurrenceCycle {
  weekly('week', 'Hàng tuần'),
  monthly('month', 'Hàng tháng'),
  yearly('year', 'Hàng năm');

  final String code;
  final String labelVi;
  const BillingRecurrenceCycle(this.code, this.labelVi);
}

class PriceHistoryPoint extends Equatable {
  final DateTime recordedAt;
  final int amountMinor;

  const PriceHistoryPoint({
    required this.recordedAt,
    required this.amountMinor,
  });

  @override
  List<Object?> get props => [recordedAt, amountMinor];
}

class RecurringServiceInput extends Equatable {
  final String id;
  final String name;
  final int currentAmountMinor;
  final BillingRecurrenceCycle cycle;
  final DateTime nextBillingDate;
  final DateTime? trialEndsAt;
  final int remindDaysBefore;
  final List<PriceHistoryPoint> priceHistory;
  final DateTime? lastUsedOrMatchedTxAt;
  final String? linkedBankTransactionId;

  const RecurringServiceInput({
    required this.id,
    required this.name,
    required this.currentAmountMinor,
    required this.cycle,
    required this.nextBillingDate,
    this.trialEndsAt,
    this.remindDaysBefore = 3,
    this.priceHistory = const <PriceHistoryPoint>[],
    this.lastUsedOrMatchedTxAt,
    this.linkedBankTransactionId,
  });

  @override
  List<Object?> get props => [
    id,
    name,
    currentAmountMinor,
    cycle,
    nextBillingDate,
    trialEndsAt,
    remindDaysBefore,
    priceHistory,
    lastUsedOrMatchedTxAt,
    linkedBankTransactionId,
  ];
}

class SubscriptionInsightAlert extends Equatable {
  final String serviceId;
  final String serviceName;
  final String
  kind; // 'renewal_soon' | 'trial_ending' | 'price_increase' | 'low_usage'
  final String messageVi;

  const SubscriptionInsightAlert({
    required this.serviceId,
    required this.serviceName,
    required this.kind,
    required this.messageVi,
  });

  @override
  List<Object?> get props => [serviceId, serviceName, kind, messageVi];
}

class SubscriptionPortfolioSummary extends Equatable {
  final int normalizedMonthlyTotalMinor;
  final int normalizedYearlyTotalMinor;
  final List<SubscriptionInsightAlert> alerts;
  final Map<String, String> matchedBankTransactionByServiceId;

  const SubscriptionPortfolioSummary({
    required this.normalizedMonthlyTotalMinor,
    required this.normalizedYearlyTotalMinor,
    required this.alerts,
    required this.matchedBankTransactionByServiceId,
  });

  @override
  List<Object?> get props => [
    normalizedMonthlyTotalMinor,
    normalizedYearlyTotalMinor,
    alerts,
    matchedBankTransactionByServiceId,
  ];
}

/// Subscription & Recurring Bills Intelligence Engine (Section 24).
/// Never auto-cancels services or initiates external payments; surfaces transparent insights & bank matches.
abstract final class SubscriptionIntelligenceEngine {
  static int normalizeToMonthlyMinor(
    int amountMinor,
    BillingRecurrenceCycle cycle,
  ) {
    return switch (cycle) {
      BillingRecurrenceCycle.weekly => (amountMinor * 52) ~/ 12,
      BillingRecurrenceCycle.monthly => amountMinor,
      BillingRecurrenceCycle.yearly => (amountMinor / 12.0).round(),
    };
  }

  static SubscriptionPortfolioSummary analyze({
    required List<RecurringServiceInput> services,
    required DateTime referenceNow,
    List<({String txId, String merchant, int amountMinor, DateTime occurredAt})>
        recentBankTransactions =
        const [],
  }) {
    var monthlyTotal = 0;
    final alerts = <SubscriptionInsightAlert>[];
    final matchedTx = <String, String>{};

    for (final svc in services) {
      monthlyTotal += normalizeToMonthlyMinor(
        svc.currentAmountMinor,
        svc.cycle,
      );

      // 1. Trial ending alert
      if (svc.trialEndsAt != null) {
        final trialDays = svc.trialEndsAt!.difference(referenceNow).inDays;
        if (trialDays >= 0 && trialDays <= 5) {
          alerts.add(
            SubscriptionInsightAlert(
              serviceId: svc.id,
              serviceName: svc.name,
              kind: 'trial_ending',
              messageVi:
                  'Gói dùng thử "${svc.name}" kết thúc sau $trialDays ngày — kiểm tra nếu bạn không muốn gia hạn tự động.',
            ),
          );
        }
      }

      // 2. Upcoming renewal reminder
      final dueDays = svc.nextBillingDate.difference(referenceNow).inDays;
      if (dueDays >= 0 && dueDays <= svc.remindDaysBefore) {
        alerts.add(
          SubscriptionInsightAlert(
            serviceId: svc.id,
            serviceName: svc.name,
            kind: 'renewal_soon',
            messageVi: 'Dịch vụ "${svc.name}" sẽ gia hạn sau $dueDays ngày.',
          ),
        );
      }

      // 3. Price hike history tracking (>= 5% increase over previous price)
      if (svc.priceHistory.isNotEmpty) {
        final sortedHist = List<PriceHistoryPoint>.from(svc.priceHistory)
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
        final prevPrice = sortedHist.last.amountMinor;
        if (prevPrice > 0 && svc.currentAmountMinor > prevPrice) {
          final hikePct =
              (((svc.currentAmountMinor - prevPrice) * 100.0) / prevPrice)
                  .round();
          if (hikePct >= 5) {
            alerts.add(
              SubscriptionInsightAlert(
                serviceId: svc.id,
                serviceName: svc.name,
                kind: 'price_increase',
                messageVi:
                    'Giá gói "${svc.name}" đã tăng $hikePct% so với kỳ trước.',
              ),
            );
          }
        }
      }

      // 4. Match against verified/confirmed bank transactions
      if (svc.linkedBankTransactionId != null &&
          svc.linkedBankTransactionId!.isNotEmpty) {
        matchedTx[svc.id] = svc.linkedBankTransactionId!;
      } else {
        final normName = svc.name.trim().toLowerCase();
        for (final tx in recentBankTransactions) {
          if (tx.merchant.toLowerCase().contains(normName) &&
              (tx.amountMinor - svc.currentAmountMinor).abs() <=
                  (svc.currentAmountMinor * 0.1).round()) {
            matchedTx[svc.id] = tx.txId;
            break;
          }
        }
      }

      // 5. Low-usage hint ONLY when concrete usage timestamp exists and > 60 days idle
      if (svc.lastUsedOrMatchedTxAt != null) {
        final idleDays = referenceNow
            .difference(svc.lastUsedOrMatchedTxAt!)
            .inDays;
        if (idleDays >= 60) {
          alerts.add(
            SubscriptionInsightAlert(
              serviceId: svc.id,
              serviceName: svc.name,
              kind: 'low_usage',
              messageVi:
                  'Chưa ghi nhận tương tác với "${svc.name}" trong $idleDays ngày qua — cân nhắc rà soát nhu cầu sử dụng.',
            ),
          );
        }
      }
    }

    return SubscriptionPortfolioSummary(
      normalizedMonthlyTotalMinor: monthlyTotal,
      normalizedYearlyTotalMinor: monthlyTotal * 12,
      alerts: alerts,
      matchedBankTransactionByServiceId: matchedTx,
    );
  }
}
