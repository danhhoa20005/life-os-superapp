import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../domain/entities/pro_utilities_entities.dart';

/// Replaces Paid Receipt OCR Scanners, Bank Loan Pro & YNAB/Monarch FIRE Wealth Planners.
class WealthToolsPage extends StatefulWidget {
  const WealthToolsPage({super.key});

  @override
  State<WealthToolsPage> createState() => _WealthToolsPageState();
}

class _WealthToolsPageState extends State<WealthToolsPage> {
  String _activeTool = 'receipt'; // 'receipt' | 'loan' | 'fire'

  // 1. Receipt Scanner State
  final TextEditingController _receiptCtrl = TextEditingController(
    text:
        'Siêu thị Co.opmart Quận 7\n'
        'Thịt bò Úc 300g 145.000\n'
        'Sữa tươi TH True Milk 42.000\n'
        'Rau củ hữu cơ Đà Lạt 58.000\n'
        'Nước rửa chén Sunlight 35.000\n'
        'Tổng thanh toán: 280.000đ',
  );

  // 2. Loan Calculator State
  final TextEditingController _loanPrincipalCtrl = TextEditingController(
    text: '1200000000',
  );
  double _loanRatePct = 8.5;
  int _loanTermMonths = 180; // 15 years
  bool _decliningBalance = true;

  // 3. FIRE Simulator State
  double _expectedReturnPct = 10.0;

  @override
  void dispose() {
    _receiptCtrl.dispose();
    _loanPrincipalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = TammySemanticColors.of(context);
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    final dash = context.watch<DashboardBloc>().state.data;

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              const LifeOsTopBrandHeader(
                title: 'Công cụ Tài chính Pro',
                showBackButton: true,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSpacing.maxContentWidth,
                  ),
                  child: LifeOsSegmentedPills<String>(
                    selected: _activeTool,
                    options: const [
                      ('receipt', 'Quét Bill AI', null),
                      ('loan', 'Lãi Vay', null),
                      ('fire', 'FIRE & 6 Lọ', null),
                    ],
                    onChanged: (v) => setState(() => _activeTool = v),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.maxContentWidth,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        2,
                        AppSpacing.md,
                        AppSpacing.xxl,
                      ),
                      children: [
                        if (_activeTool == 'receipt')
                          _buildReceiptScannerView(
                            context,
                            c,
                            user.id,
                            wallets.isNotEmpty ? wallets.first.id : null,
                          ),
                        if (_activeTool == 'loan')
                          _buildLoanCalculatorView(context, c),
                        if (_activeTool == 'fire')
                          _buildFireAndSixJarsView(
                            context,
                            c,
                            netWorthMinor: dash.netWorthMinor,
                            monthlyIncomeMinor: dash.monthlyIncomeMinor > 0
                                ? dash.monthlyIncomeMinor
                                : 25000000,
                            monthlyExpenseMinor: dash.monthlyExpenseMinor > 0
                                ? dash.monthlyExpenseMinor
                                : 12000000,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptScannerView(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    String? defaultWalletId,
  ) {
    final parsed = SmartReceiptParserEngine.parse(_receiptCtrl.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LifeOsMintHeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.document_scanner_outlined,
                    size: 20,
                    color: c.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bóc tách Hóa đơn & Bill Siêu thị / GrabFood',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('receipt_raw_text_input'),
                controller: _receiptCtrl,
                maxLines: 5,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintMaxLines: 3,
                  hintText: 'Dán nội dung hóa đơn',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Parsed Line Items Card
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    parsed.merchant,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      VndAmount.format(parsed.totalMinor),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: c.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LifeOsStatusPill(
                icon: Icons.auto_awesome_rounded,
                label:
                    '${parsed.suggestedCategory} · ${parsed.items.length} món bóc tách',
                tone: LifeOsAccentTone.emerald,
              ),
              if (parsed.items.isNotEmpty) ...[
                const Divider(height: 22),
                ...parsed.items.map(
                  (it) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '• ${it.name}',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          VndAmount.format(it.amountMinor),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () => context.go('/family'),
                  icon: const Icon(Icons.call_split_rounded, size: 17),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Chia nhóm'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const Key('commit_scanned_receipt_button'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: (defaultWalletId == null || parsed.totalMinor <= 0)
                      ? null
                      : () {
                          context.read<TransactionActionBloc>().add(
                            TransactionCreateSubmitted(
                              operationId: const Uuid().v4(),
                              userId: userId,
                              walletId: defaultWalletId,
                              categoryName: parsed.suggestedCategory,
                              kind: TransactionKind.expense,
                              amountMinor: parsed.totalMinor,
                              merchant: parsed.merchant,
                              note: 'Quét Bill AI (${parsed.items.length} món)',
                              occurredAt: DateTime.now(),
                            ),
                          );
                          LifeOsTopToast.fromSnackBar(
                            context,
                            SnackBar(
                              content: Text(
                                '✓ Đã ghi hóa đơn "${parsed.merchant}" (${VndAmount.format(parsed.totalMinor)}) vào Sổ cái.',
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Ghi vào Ví'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoanCalculatorView(BuildContext context, TammySemanticColors c) {
    final principal = VndAmount.tryParseInput(_loanPrincipalCtrl.text) ?? 0;
    final preview = LoanAmortizationEngine.calculate(
      principalMinor: principal,
      annualRatePct: _loanRatePct,
      termMonths: _loanTermMonths,
      decliningBalance: _decliningBalance,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Máy tính Vay Mua Nhà / Mua Xe Ngân hàng',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15.5,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              LifeOsSegmentedPills<bool>(
                selected: _decliningBalance,
                options: const [
                  (true, 'Dư nợ giảm dần', null),
                  (false, 'Trả đều hằng tháng', null),
                ],
                onChanged: (v) => setState(() => _decliningBalance = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _loanPrincipalCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Số tiền gốc vay (VND)',
                  suffixText: 'VND',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Lãi suất năm: ${_loanRatePct.toStringAsFixed(1)}% / năm',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              Slider(
                value: _loanRatePct,
                min: 4.0,
                max: 16.0,
                divisions: 24,
                activeColor: c.primary,
                onChanged: (v) => setState(() => _loanRatePct = v),
              ),
              Text(
                'Kỳ hạn vay: $_loanTermMonths tháng (${(_loanTermMonths / 12).toStringAsFixed(0)} năm)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              Slider(
                value: _loanTermMonths.toDouble(),
                min: 12,
                max: 300,
                divisions: 24,
                activeColor: c.primary,
                onChanged: (v) => setState(() => _loanTermMonths = v.round()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LifeOsMintHeroCard(
          child: Column(
            children: [
              _ResultMetricRow(
                label: 'Gốc + Lãi tháng đầu tiên',
                value: VndAmount.format(preview.firstMonthPaymentMinor),
                highlightColor: c.primary,
              ),
              const Divider(height: 20),
              _ResultMetricRow(
                label: 'Gốc + Lãi tháng cuối cùng',
                value: VndAmount.format(preview.lastMonthPaymentMinor),
              ),
              const Divider(height: 20),
              _ResultMetricRow(
                label: 'Tổng tiền lãi phải trả',
                value: VndAmount.format(preview.totalInterestMinor),
                highlightColor: c.error,
              ),
              const Divider(height: 20),
              _ResultMetricRow(
                label: 'Tổng gốc + lãi toàn kỳ',
                value: VndAmount.format(preview.totalPayableMinor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFireAndSixJarsView(
    BuildContext context,
    TammySemanticColors c, {
    required int netWorthMinor,
    required int monthlyIncomeMinor,
    required int monthlyExpenseMinor,
  }) {
    final sim = FireWealthSimulatorEngine.simulate(
      currentNetWorthMinor: netWorthMinor,
      monthlyIncomeMinor: monthlyIncomeMinor,
      monthlyExpenseMinor: monthlyExpenseMinor,
      expectedAnnualReturnPct: _expectedReturnPct,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LifeOsMintHeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.trending_up_rounded, size: 20, color: c.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mốc Tự do Tài chính FIRE (Quy tắc 4%)',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                VndAmount.format(sim.fireNumberMinor),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: c.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Thời gian ước tính đạt tự do tài chính: ${sim.yearsToFire.toStringAsFixed(1)} năm · Dự phóng 10 năm tới: ${VndAmount.formatCompact(sim.projected10YearNetWorthMinor)}',
                style: TextStyle(fontSize: 12.5, color: c.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                'Tỷ suất sinh lời kỳ vọng: ${_expectedReturnPct.toStringAsFixed(1)}% / năm',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              Slider(
                value: _expectedReturnPct,
                min: 5.0,
                max: 18.0,
                divisions: 26,
                activeColor: c.primary,
                onChanged: (v) => setState(() => _expectedReturnPct = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Phân bổ Thu nhập 6 Chiếc Lọ Chuẩn Quốc tế (${VndAmount.format(monthlyIncomeMinor)}/tháng)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...sim.sixJarsMonthlyAllocation.entries.map(
                (jar) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ResultMetricRow(
                    label: jar.key,
                    value: VndAmount.format(jar.value),
                    highlightColor: c.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultMetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? highlightColor;

  const _ResultMetricRow({
    required this.label,
    required this.value,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: highlightColor ?? c.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
