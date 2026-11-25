import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/services/native_receipt_picker_bridge.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../family/domain/entities/family_entities.dart';
import '../../../family/domain/usecases/family_usecases.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../domain/services/receipt_intelligence_engine.dart';

/// Camera/Gallery Receipt Picker + VAT/Discount Verification + Itemized Group Split Panel (Section 19).
class ReceiptItemizedSplitPanel extends StatefulWidget {
  final String rawOcrText;
  final String currentUserId;
  final String currentUserName;
  final ValueChanged<PickedReceiptImage>? onImagePicked;

  const ReceiptItemizedSplitPanel({
    super.key,
    required this.rawOcrText,
    required this.currentUserId,
    required this.currentUserName,
    this.onImagePicked,
  });

  @override
  State<ReceiptItemizedSplitPanel> createState() =>
      _ReceiptItemizedSplitPanelState();
}

class _ReceiptItemizedSplitPanelState extends State<ReceiptItemizedSplitPanel> {
  final Map<String, Set<String>> _assigneesByItemId = <String, Set<String>>{};
  PickedReceiptImage? _pickedImage;

  FamilyBloc? _maybeFamBloc(BuildContext context) {
    try {
      return context.watch<FamilyBloc>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickReceiptImage(BuildContext context, {required bool camera}) async {
    final bridge = sl.isRegistered<NativeReceiptPickerBridge>()
        ? sl<NativeReceiptPickerBridge>()
        : const NativeReceiptPickerBridge();
    final img = camera
        ? await bridge.captureFromCamera()
        : await bridge.pickFromGallery();
    if (!context.mounted) return;
    if (img == null) {
      LifeOsTopToast.show(
        context,
        camera
            ? 'Chưa chụp ảnh mới — bạn có thể dán nội dung hóa đơn bên dưới.'
            : 'Chưa chọn ảnh hóa đơn nào.',
        kind: LifeOsToastKind.info,
      );
      return;
    }
    setState(() => _pickedImage = img);
    widget.onImagePicked?.call(img);
    LifeOsTopToast.show(
      context,
      'Đã đính kèm ảnh hóa đơn "${img.fileName}" — hãy kiểm tra các món bên dưới trước khi lưu.',
      kind: LifeOsToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final baseAnalysis = ReceiptIntelligenceEngine.analyzeOcrText(
      widget.rawOcrText,
    );
    final famBloc = _maybeFamBloc(context);
    final activeFamily = famBloc?.state.activeFamily;
    final members = activeFamily?.members ?? const <FamilyMemberInfo>[];

    final decoratedItems = baseAnalysis.items.map((item) {
      final assigned = _assigneesByItemId[item.id];
      if (assigned == null || assigned.isEmpty) return item;
      return item.copyWith(assignedMemberIds: assigned.toList());
    }).toList();

    final analysis = StructuredReceiptAnalysis(
      documentType: baseAnalysis.documentType,
      merchantName: baseAnalysis.merchantName,
      items: decoratedItems,
      itemsSubtotalMinor: baseAnalysis.itemsSubtotalMinor,
      vatMinor: baseAnalysis.vatMinor,
      surchargeMinor: baseAnalysis.surchargeMinor,
      discountMinor: baseAnalysis.discountMinor,
      statedTotalMinor: baseAnalysis.statedTotalMinor,
      computedNetTotalMinor: baseAnalysis.computedNetTotalMinor,
      discrepancyMinor: baseAnalysis.discrepancyMinor,
    );

    final memberIds = members.map((m) => m.userId).toList();
    final itemizedShares = memberIds.length >= 2
        ? ReceiptIntelligenceEngine.computeItemizedGroupShares(
            analysis: analysis,
            allParticipantIds: memberIds,
          )
        : const <String, int>{};

    return LifeOsSoftCard(
      key: const Key('receipt_itemized_split_panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LifeOsStatusPill(
                icon: Icons.receipt_long_rounded,
                label: analysis.documentType.labelVi,
                tone: LifeOsAccentTone.blue,
              ),
              LifeOsStatusPill(
                icon: analysis.isTotalVerified
                    ? Icons.verified_rounded
                    : Icons.warning_amber_rounded,
                label: analysis.isTotalVerified
                    ? 'Tổng tiền khớp từng món'
                    : (analysis.discrepancyMinor != 0
                          ? 'Lệch ${VndAmount.format(analysis.discrepancyMinor.abs())} — cần kiểm tra'
                          : 'Chưa có tổng tiền'),
                tone: analysis.isTotalVerified
                    ? LifeOsAccentTone.emerald
                    : LifeOsAccentTone.coral,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('receipt_pick_gallery_btn'),
                onPressed: () => _pickReceiptImage(context, camera: false),
                icon: const Icon(Icons.photo_library_outlined, size: 17),
                label: const Text('Chọn ảnh hóa đơn'),
              ),
              OutlinedButton.icon(
                key: const Key('receipt_capture_camera_btn'),
                onPressed: () => _pickReceiptImage(context, camera: true),
                icon: const Icon(Icons.camera_alt_outlined, size: 17),
                label: const Text('Chụp hóa đơn'),
              ),
            ],
          ),
          if (_pickedImage != null) ...[
            const SizedBox(height: 8),
            Text(
              'Ảnh đã chọn: ${_pickedImage!.fileName} (${(_pickedImage!.sizeBytes / 1024).toStringAsFixed(1)} KB)',
              softWrap: true,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (analysis.vatMinor > 0 ||
              analysis.surchargeMinor > 0 ||
              analysis.discountMinor > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                if (analysis.vatMinor > 0)
                  Text(
                    'VAT: +${VndAmount.format(analysis.vatMinor)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                if (analysis.surchargeMinor > 0)
                  Text(
                    'Phụ thu: +${VndAmount.format(analysis.surchargeMinor)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                if (analysis.discountMinor > 0)
                  Text(
                    'Giảm giá: -${VndAmount.format(analysis.discountMinor)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.success,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ],
          if (members.length >= 2 && analysis.items.isNotEmpty) ...[
            const Divider(height: 20),
            LifeOsDetailsDiscloseSection(
              toggleKey: const Key('receipt_itemized_member_split_toggle'),
              label: 'Chia chi tiết từng món cho thành viên nhóm',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Chạm tên thành viên cho món riêng; để trống sẽ tự chia đều phần chung + phân bổ thuế/giảm giá chính xác đến từng đồng.',
                    softWrap: true,
                    style: TextStyle(fontSize: 11.8, color: c.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  for (final it in analysis.items) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${it.name} · ${VndAmount.format(it.lineTotalMinor)}',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 12.8,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: members.map((m) {
                              final set =
                                  _assigneesByItemId[it.id] ?? <String>{};
                              final selected = set.contains(m.userId);
                              return FilterChip(
                                visualDensity: VisualDensity.compact,
                                selected: selected,
                                label: Text(m.fullName.split(' ').last),
                                onSelected: (val) {
                                  setState(() {
                                    final next = Set<String>.from(set);
                                    if (val) {
                                      next.add(m.userId);
                                    } else {
                                      next.remove(m.userId);
                                    }
                                    _assigneesByItemId[it.id] = next;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 16),
                  for (final m in members)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              m.fullName,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 12.6,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            VndAmount.format(itemizedShares[m.userId] ?? 0),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: c.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    key: const Key('receipt_commit_itemized_split_btn'),
                    onPressed:
                        (analysis.requiresManualTotalReview || activeFamily == null)
                        ? null
                        : () {
                            final exactMap = <String, int>{
                              for (final e in itemizedShares.entries)
                                if (e.value > 0) e.key: e.value,
                            };
                            final nameMap = <String, String>{
                              for (final m in members)
                                if (exactMap.containsKey(m.userId))
                                  m.userId: m.fullName,
                            };
                            context.read<FamilyBloc>().add(
                              SharedBillSplitCreated(
                                CreateSharedBillSplitParams(
                                  familyId: activeFamily.id,
                                  title:
                                      'Hóa đơn ${analysis.merchantName} (chia theo món)',
                                  topic: SharedExpenseTopic.shopping,
                                  totalAmountMinor: analysis.effectiveTotalMinor,
                                  paidByUserId: widget.currentUserId,
                                  paidByName: widget.currentUserName,
                                  splitMethod: SplitMethod.exact,
                                  participantIds: exactMap.keys.toList(),
                                  participantNames: nameMap,
                                  rawInputValuesByUserId: exactMap,
                                ),
                              ),
                            );
                            LifeOsTopToast.show(
                              context,
                              'Đã gửi bảng chia theo món "${analysis.merchantName}" vào nhóm ${activeFamily.name}.',
                              kind: LifeOsToastKind.success,
                            );
                          },
                    icon: const Icon(Icons.groups_rounded, size: 17),
                    label: const Text('Lưu chia theo món vào Nhóm'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
