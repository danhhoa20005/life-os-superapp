import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/authentication/presentation/bloc/auth_bloc.dart';
import '../../features/family/domain/entities/family_entities.dart';
import '../../features/family/domain/usecases/family_usecases.dart';
import '../../features/family/presentation/bloc/family_bloc.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import '../../features/transactions/presentation/bloc/transaction_bloc.dart';
import '../../features/transactions/presentation/bloc/transaction_event.dart';
import '../di/dependency_injection.dart';
import '../services/native_voice_assistant_bridge.dart';
import '../utils/vnd_amount.dart';
import '../utils/voice_financial_nlp_engine.dart';
import 'pro_max_widgets.dart';
import 'status_widgets.dart';

Future<void> showVoiceSmartCaptureSheet(
  BuildContext context, {
  bool autoStartListening = false,
  String? initialTranscript,
}) async {
  final authUser = context.read<AuthBloc>().state.user;
  if (authUser == null) return;

  final txListBloc = context.read<TransactionListBloc>();
  final txActionBloc = context.read<TransactionActionBloc>();
  final familyBloc = context.read<FamilyBloc>();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      return MultiBlocProvider(
        providers: [
          BlocProvider<TransactionListBloc>.value(value: txListBloc),
          BlocProvider<TransactionActionBloc>.value(value: txActionBloc),
          BlocProvider<FamilyBloc>.value(value: familyBloc),
        ],
        child: _VoiceSmartCaptureSheetBody(
          userId: authUser.id,
          userName: authUser.fullName,
          autoStartListening: autoStartListening,
          initialTranscript: initialTranscript,
        ),
      );
    },
  );
}

class _VoiceSmartCaptureSheetBody extends StatefulWidget {
  final String userId;
  final String userName;
  final bool autoStartListening;
  final String? initialTranscript;

  const _VoiceSmartCaptureSheetBody({
    required this.userId,
    required this.userName,
    required this.autoStartListening,
    this.initialTranscript,
  });

  @override
  State<_VoiceSmartCaptureSheetBody> createState() => _VoiceSmartCaptureSheetBodyState();
}

class _VoiceSmartCaptureSheetBodyState extends State<_VoiceSmartCaptureSheetBody> {
  static const List<({String chip, String sentence})> _voiceExamples = [
    (
      chip: '🍲 Chia đều 3 người',
      sentence: 'Ăn lẩu bò bốn trăm năm mươi nghìn chia đều 3 người',
    ),
    (
      chip: '⚡ Chia theo tên nhóm',
      sentence: 'Tiền điện nước 1 triệu 2 chia cho Hòa, Minh và Lan',
    ),
    (
      chip: '⚖️ Chia phần còn lại',
      sentence: 'Ăn tối 500 nghìn Minh 200 nghìn còn lại Hòa chịu',
    ),
    (
      chip: '🛒 Tách hóa đơn siêu thị',
      sentence: 'Đi siêu thị 500 nghìn gồm ăn uống 320 nghìn và việc nhà 180 nghìn',
    ),
    (
      chip: '⚡ Ghi 3 khoản 1 câu',
      sentence: 'Sáng ăn phở 65 nghìn đổ xăng 90 nghìn chiều nhận lương 18 triệu rưỡi',
    ),
  ];

  late final TextEditingController _textCtrl;
  StreamSubscription<VoiceAssistantSignal>? _voiceSub;
  bool _isListening = false;
  double _rmsDb = 0.0;
  String? _voiceStatusHint;
  String? _selectedWalletId;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialTranscript ?? '');
    final bridge = sl<NativeVoiceAssistantBridge>();
    _voiceSub = bridge.watchSignals().listen((sig) {
      if (!mounted) return;
      switch (sig) {
        case VoiceStateSignal(:final status):
          setState(() {
            _isListening = status == 'listening';
            _voiceStatusHint = status == 'listening'
                ? 'Đang lắng nghe giọng nói tiếng Việt...'
                : (status == 'processing' ? 'Đang phân tích câu...' : null);
          });
        case VoiceRmsSignal(:final rmsDb):
          setState(() => _rmsDb = rmsDb);
        case VoiceTranscriptSignal(:final text, :final isFinal):
          setState(() {
            _textCtrl.text = text;
            _textCtrl.selection = TextSelection.collapsed(offset: text.length);
            if (isFinal) {
              _isListening = false;
              _rmsDb = 0.0;
              _voiceStatusHint = 'Đã nhận diện giọng nói hoàn tất.';
            }
          });
        case VoiceErrorSignal(:final message):
          setState(() {
            _isListening = false;
            _rmsDb = 0.0;
            _voiceStatusHint = message;
          });
      }
    });

    if (widget.autoStartListening) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toggleVoiceListening());
    }
  }

  @override
  void dispose() {
    _voiceSub?.cancel();
    sl<NativeVoiceAssistantBridge>().stopListening();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleVoiceListening() async {
    final bridge = sl<NativeVoiceAssistantBridge>();
    if (_isListening) {
      await bridge.stopListening();
      if (mounted) {
        setState(() {
          _isListening = false;
          _rmsDb = 0.0;
        });
      }
      return;
    }
    setState(() {
      _isListening = true;
      _voiceStatusHint = 'Hãy nói tự nhiên, VD: “Ăn lẩu 450k chia đều 3 người”...';
    });
    final res = await bridge.startListening();
    if (res == 'UNSUPPORTED' && mounted) {
      setState(() {
        _isListening = false;
        _voiceStatusHint = 'Chế độ thử nghiệm: Chọn câu mẫu hoặc nhập giọng nói bên dưới.';
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = clip?.text?.trim() ?? '';
    if (txt.isEmpty) {
      if (mounted) {
        setState(() => _voiceStatusHint = 'Bộ nhớ tạm (Clipboard) hiện đang trống.');
      }
      return;
    }
    setState(() {
      _textCtrl.text = txt;
      _voiceStatusHint = 'Đã tự động đọc nội dung vừa sao chép từ Clipboard!';
    });
  }

  Future<void> _executeAnalysis(
    BuildContext context,
    VoiceFinancialAnalysisResult result,
    String targetWalletId,
    FamilyEntity? activeFamily,
  ) async {
    const uuid = Uuid();
    final txActionBloc = context.read<TransactionActionBloc>();
    final familyBloc = context.read<FamilyBloc>();

    switch (result.intentKind) {
      case VoiceSentenceIntentKind.groupBillSplit:
        final split = result.groupSplit!;
        var targetFamilyId = activeFamily?.id;
        if (targetFamilyId == null) {
          // Automatically bootstrap a quick collaboration space if user hasn't created one yet!
          familyBloc.add(
            FamilyCreateSubmitted(
              userId: widget.userId,
              userName: widget.userName,
              familyName: 'Nhóm Chia Tiền Nhanh',
              spaceType: CollaborationSpaceType.group,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 220));
          targetFamilyId = familyBloc.state.activeFamily?.id;
        }
        if (targetFamilyId != null) {
          familyBloc.add(
            SharedBillSplitCreated(
              CreateSharedBillSplitParams(
                familyId: targetFamilyId,
                title: split.title,
                topic: split.topic,
                paidByUserId: widget.userId,
                paidByName: widget.userName,
                totalAmountMinor: split.totalAmountMinor,
                splitMethod: split.splitMethod,
                participantIds: split.shares.map((s) => s.participantId).toList(),
                participantNames: {
                  for (final s in split.shares) s.participantId: s.displayName,
                },
                rawInputValuesByUserId: split.rawInputValuesByUserId,
                choreOrTaskNote: 'Phân tích tự động bằng Giọng nói AI',
              ),
            ),
          );
        }
        if (context.mounted) {
          Navigator.of(context).pop();
          LifeOsTopToast.fromSnackBar(context, 
            SnackBar(
              content: Text(
                '✓ Đã chia hóa đơn "${split.title}" (${VndAmount.format(split.totalAmountMinor)}) cho ${split.shares.length} người!',
              ),
            ),
          );
        }

      case VoiceSentenceIntentKind.multiCategoryReceipt:
        final rec = result.multiCategoryReceipt!;
        txActionBloc.add(
          TransactionCreateSubmitted(
            operationId: uuid.v4(),
            userId: widget.userId,
            walletId: targetWalletId,
            categoryName: rec.splitLines.first.categoryName,
            kind: TransactionKind.expense,
            amountMinor: rec.totalAmountMinor,
            merchant: rec.merchant,
            note: 'Tách khoản bằng Giọng nói AI',
            occurredAt: DateTime.now(),
            splitLines: rec.splitLines,
          ),
        );
        if (context.mounted) {
          Navigator.of(context).pop();
        }

      case VoiceSentenceIntentKind.batchTransactions:
      case VoiceSentenceIntentKind.singleTransaction:
        for (final entry in result.personalEntries) {
          txActionBloc.add(
            TransactionCreateSubmitted(
              operationId: uuid.v4(),
              userId: widget.userId,
              walletId: targetWalletId,
              categoryId: entry.categoryId,
              categoryName: entry.categoryName,
              kind: entry.kind,
              amountMinor: entry.amountMinor,
              merchant: entry.merchant,
              note: 'Ghi tự động bằng Giọng nói AI',
              occurredAt: DateTime.now(),
            ),
          );
        }
        if (context.mounted) {
          Navigator.of(context).pop();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    final activeFamily = context.watch<FamilyBloc>().state.activeFamily;
    final knownMembers = activeFamily?.members ?? const <FamilyMemberInfo>[];

    final resolvedWalletId = _selectedWalletId != null &&
            wallets.any((w) => w.id == _selectedWalletId)
        ? _selectedWalletId!
        : (wallets.isNotEmpty ? wallets.first.id : 'wallet_cash_default');

    final analysis = VoiceFinancialNlpEngine.analyze(
      _textCtrl.text,
      currentUserId: widget.userId,
      currentUserName: widget.userName,
      knownMembers: knownMembers,
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header + Clipboard Quick Read
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF064E1E), Color(0xFF10B981)],
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trợ lý Giọng nói & Phân tích Câu Chia Tiền',
                          softWrap: true,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          'Tự bóc tách số tiền nói, tách hóa đơn & chia bill nhóm',
                          softWrap: true,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_go_rounded, size: 16),
                    label: const Text('Clipboard'),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 2. Live Voice Waveform & Tactile Mic Trigger Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isListening
                        ? const [Color(0xFF064E1E), Color(0xFF0B7A2A)]
                        : [c.surfaceRaised, c.surfaceRaised],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _isListening ? const Color(0xFF63E6BE) : c.separator,
                    width: _isListening ? 1.5 : 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      key: const Key('voice_mic_toggle_button'),
                      onTap: _toggleVoiceListening,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isListening ? const Color(0xFFEF4444) : c.primary,
                          boxShadow: [
                            BoxShadow(
                              color: (_isListening ? const Color(0xFFEF4444) : c.primary)
                                  .withValues(alpha: 0.34),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isListening
                                ? 'Đang nghe... Nhấn nút đỏ khi nói xong'
                                : 'Nhấn Mic để nói tiếng Việt tự nhiên',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _isListening ? Colors.white : c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 22,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _VoiceWaveformPainter(
                                isListening: _isListening,
                                rmsDb: _rmsDb,
                                activeColor: _isListening ? const Color(0xFF8CE99A) : c.primary,
                                idleColor: c.separator,
                              ),
                            ),
                          ),
                          if (_voiceStatusHint != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              _voiceStatusHint!,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 11,
                                color: _isListening
                                    ? Colors.white.withValues(alpha: 0.85)
                                    : c.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 3. 1-Tap Spoken Sentence Presets
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _voiceExamples.map((ex) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(ex.chip, style: const TextStyle(fontSize: 11.5)),
                        onPressed: () {
                          setState(() {
                            _textCtrl.text = ex.sentence;
                            _voiceStatusHint = null;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),

              // 4. Transcript Input Box
              TextField(
                key: const Key('voice_transcript_input'),
                controller: _textCtrl,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Câu nói / Nội dung cần phân tích & chia tiền',
                  hintText: 'VD: Ăn lẩu bò 450 nghìn chia đều 3 người',
                  suffixIcon: _textCtrl.text.isNotEmpty
                      ? IconButton(
                          onPressed: () => setState(() => _textCtrl.clear()),
                          icon: const Icon(Icons.clear_rounded, size: 18),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),

              // 5. Real-Time Structured NLP Breakdown Card
              if (analysis != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: c.primary.withValues(alpha: 0.35), width: 1.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 16, color: c.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              analysis.summaryHeadline,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: c.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 18),
                      if (analysis.groupSplit != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${analysis.groupSplit!.title} · ${analysis.groupSplit!.topic.displayLabel}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                            Text(
                              VndAmount.format(analysis.groupSplit!.totalAmountMinor),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: c.primary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...analysis.groupSplit!.shares.map((sh) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.person_outline_rounded,
                                        size: 16, color: c.secondary),
                                    const SizedBox(width: 6),
                                    Text(
                                      sh.percentage != null
                                          ? '${sh.displayName} (${sh.percentage}%)'
                                          : sh.displayName,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  VndAmount.format(sh.amountMinor),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 4),
                        Text(
                          activeFamily != null
                              ? 'Không gian nhận: ${activeFamily.name}'
                              : 'Sẽ tự động khởi tạo "Nhóm Chia Tiền Nhanh" để lưu bảng chia',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ] else if (analysis.multiCategoryReceipt != null) ...[
                        ...analysis.multiCategoryReceipt!.splitLines.map((line) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                ProCategoryStyle.buildCategoryBadge(line.categoryName, size: 32),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    line.categoryName,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  VndAmount.format(line.amountMinor),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ] else ...[
                        ...analysis.personalEntries.map((item) {
                          final isInc = item.kind == TransactionKind.income;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                ProCategoryStyle.buildCategoryBadge(
                                  item.categoryName,
                                  isCredit: isInc,
                                  size: 34,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.merchant,
                                        softWrap: true,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        item.categoryName,
                                        style: Theme.of(context).textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  VndAmount.format(
                                    isInc ? item.amountMinor : -item.amountMinor,
                                    showPlus: true,
                                  ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: isInc ? c.success : c.textPrimary,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      if (analysis.intentKind != VoiceSentenceIntentKind.groupBillSplit &&
                          wallets.length > 1) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: resolvedWalletId,
                          decoration: const InputDecoration(
                            labelText: 'Chọn ví ghi nhận',
                            isDense: true,
                          ),
                          items: wallets
                              .map(
                                (w) => DropdownMenuItem(
                                  value: w.id,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(w.name),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedWalletId = v);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('confirm_voice_analysis_button'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () =>
                      _executeAnalysis(context, analysis, resolvedWalletId, activeFamily),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: Text(
                    analysis.intentKind == VoiceSentenceIntentKind.groupBillSplit
                        ? 'Xác nhận Chia Hóa Đơn Nhóm (${analysis.groupSplit!.shares.length} người)'
                        : 'Xác nhận Ghi Sổ Tự Động',
                  ),
                ),
              ] else
                const SemanticStatusBadge(
                  kind: SemanticStatusKind.info,
                  label:
                      'Mẹo: Nói "Ăn lẩu 450k chia đều 3 người" hoặc "Phở 65k đổ xăng 90k" để xem phân tích tức thì.',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  final bool isListening;
  final double rmsDb;
  final Color activeColor;
  final Color idleColor;

  const _VoiceWaveformPainter({
    required this.isListening,
    required this.rmsDb,
    required this.activeColor,
    required this.idleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 24;
    final spacing = size.width / barCount;
    final normRms = ((rmsDb + 2.0) / 12.0).clamp(0.18, 1.0);
    final paint = Paint()
      ..color = isListening ? activeColor : idleColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2;

    for (var i = 0; i < barCount; i++) {
      final x = i * spacing + spacing / 2;
      final wave = math.sin((i / barCount) * math.pi * 2.5).abs();
      final factor = isListening ? (0.25 + 0.75 * wave * normRms) : 0.22;
      final h = (size.height * factor).clamp(4.0, size.height);
      final y0 = (size.height - h) / 2;
      canvas.drawLine(Offset(x, y0), Offset(x, y0 + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) {
    return oldDelegate.isListening != isListening || oldDelegate.rmsDb != rmsDb;
  }
}
