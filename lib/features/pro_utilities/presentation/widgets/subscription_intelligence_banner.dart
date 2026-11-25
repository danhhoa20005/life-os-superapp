import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../domain/entities/pro_utilities_entities.dart';
import '../../domain/services/subscription_intelligence_engine.dart';

/// Subscription & Recurring Service Intelligence Banner (Section 24).
/// Surfaces upcoming renewal alerts, bank transaction matches, and low-usage warnings
/// without ever auto-cancelling or triggering external charges.
class SubscriptionIntelligenceBanner extends StatelessWidget {
  final List<SubscriptionWarrantyEntity> subscriptions;
  final List<TransactionEntity> recentTransactions;
  final DateTime referenceNow;

  const SubscriptionIntelligenceBanner({
    super.key,
    required this.subscriptions,
    this.recentTransactions = const <TransactionEntity>[],
    required this.referenceNow,
  });

  @override
  Widget build(BuildContext context) {
    if (subscriptions.isEmpty) return const SizedBox.shrink();
    final c = TammySemanticColors.of(context);

    final inputs = subscriptions.map((s) {
      final cycle = s.cycle == SubscriptionCycle.yearly
          ? BillingRecurrenceCycle.yearly
          : BillingRecurrenceCycle.monthly;
      return RecurringServiceInput(
        id: s.id,
        name: s.title,
        currentAmountMinor: s.amountMinor,
        cycle: cycle,
        nextBillingDate: s.nextBillingOrExpiryDate,
        remindDaysBefore: 5,
      );
    }).toList();

    final bankTxs = recentTransactions
        .where((t) => !t.isReversed && t.kind == TransactionKind.expense)
        .take(40)
        .map(
          (t) => (
            txId: t.id,
            merchant: t.merchant,
            amountMinor: t.amountMinor,
            occurredAt: t.occurredAt,
          ),
        )
        .toList();

    final summary = SubscriptionIntelligenceEngine.analyze(
      services: inputs,
      referenceNow: referenceNow,
      recentBankTransactions: bankTxs,
    );

    if (summary.alerts.isEmpty &&
        summary.matchedBankTransactionByServiceId.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LifeOsSoftCard(
        key: const Key('subscription_intelligence_banner'),
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const LifeOsIconSquircle(
                  icon: Icons.auto_awesome_rounded,
                  tone: LifeOsAccentTone.amber,
                  size: 30,
                  iconSize: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Phân tích Gói đăng ký & Đối khớp Giao dịch',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                if (summary.matchedBankTransactionByServiceId.isNotEmpty)
                  LifeOsStatusPill(
                    label:
                        'Khớp ${summary.matchedBankTransactionByServiceId.length} GD',
                    tone: LifeOsAccentTone.emerald,
                  ),
              ],
            ),
            if (summary.alerts.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final a in summary.alerts.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${a.messageVi}',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12.2,
                      height: 1.32,
                      color: c.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
