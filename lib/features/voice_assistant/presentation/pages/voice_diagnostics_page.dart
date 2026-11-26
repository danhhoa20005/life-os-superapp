import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../data/datasources/voice_native_channel_datasource.dart';
import '../../domain/entities/voice_engine_capability.dart';
import '../../domain/entities/voice_model_package.dart';
import '../../domain/services/endpoint_policy.dart';
import '../../domain/services/voice_diagnostics.dart';
import '../bloc/voice_assistant_bloc.dart';
import '../bloc/voice_assistant_event.dart';
import '../bloc/voice_assistant_state.dart';

/// Developer & Support Voice Diagnostics screen (`Section 14` + `Section 11/12`).
///
/// Strictly guarantees ZERO transcript, ZERO account numbers, ZERO monetary values,
/// and ZERO raw audio in display and sanitized report exports.
class VoiceDiagnosticsPage extends StatefulWidget {
  const VoiceDiagnosticsPage({super.key});

  @override
  State<VoiceDiagnosticsPage> createState() => _VoiceDiagnosticsPageState();
}

class _VoiceDiagnosticsPageState extends State<VoiceDiagnosticsPage> {
  bool _runningSelfTest = false;
  Map<String, dynamic>? _selfTestResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<VoiceAssistantBloc>().add(const VoiceDiagnosticsRefreshed());
    });
  }

  Future<void> _runMicrophoneSelfTest() async {
    if (_runningSelfTest) return;
    setState(() => _runningSelfTest = true);
    try {
      final ds = sl.isRegistered<VoiceNativeChannelDataSource>()
          ? sl<VoiceNativeChannelDataSource>()
          : VoiceNativeChannelDataSource();
      final voiceState = context.read<VoiceAssistantBloc>().state;
      final hasVerifiedTranscript = voiceState.effectiveText.trim().isNotEmpty;
      final res = await ds.runMicrophoneSelfTest(
        hasVerifiedTranscript: hasVerifiedTranscript,
      );
      if (!mounted) return;
      setState(() => _selfTestResult = res);
      final micOpened = res['micOpened'] == true;
      final hasSignal = res['hasSignal'] == true;
      final passed = micOpened && hasSignal;
      final reasonText =
          res['reason'] ?? res['message'] ?? res['errorCode'] ?? 'không hỗ trợ';
      LifeOsTopToast.show(
        context,
        passed
            ? 'Kiểm tra micro hoàn tất: mở được mic và có tín hiệu PCM thật.'
            : (micOpened
                  ? 'Mở được mic nhưng chưa có tín hiệu âm thanh ($reasonText).'
                  : 'Không mở được micro ($reasonText).'),
        kind: passed ? LifeOsToastKind.success : LifeOsToastKind.warning,
      );
    } finally {
      if (mounted) {
        setState(() => _runningSelfTest = false);
      }
    }
  }

  Future<void> _copySanitizedReport(VoiceDiagnosticsReport report) async {
    await Clipboard.setData(ClipboardData(text: report.toSanitizedJson()));
    if (!mounted) return;
    LifeOsTopToast.show(
      context,
      'Đã sao chép báo cáo chẩn đoán đã loại bỏ dữ liệu nhạy cảm.',
      kind: LifeOsToastKind.success,
    );
  }

  String _formatBytesMb(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final palette = TammySemanticColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chẩn đoán Giọng nói'),
        actions: [
          IconButton(
            key: const Key('voice_diag_refresh_btn'),
            tooltip: 'Làm mới chẩn đoán',
            onPressed: () {
              context.read<VoiceAssistantBloc>().add(
                const VoiceDiagnosticsRefreshed(),
              );
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: BlocConsumer<VoiceAssistantBloc, VoiceAssistantState>(
        listenWhen: (prev, next) =>
            next.toastMessageVi != null &&
            next.toastMessageVi != prev.toastMessageVi,
        listener: (context, state) {
          final msg = state.toastMessageVi;
          if (msg != null) {
            LifeOsTopToast.show(
              context,
              msg,
              kind: state.isToastError
                  ? LifeOsToastKind.error
                  : LifeOsToastKind.info,
            );
            context.read<VoiceAssistantBloc>().add(const VoiceToastCleared());
          }
        },
        builder: (context, state) {
          final diag = state.diagnostics;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxxl,
            ),
            children: [
              // Privacy Guarantee Banner
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: palette.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: palette.primary,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Chẩn đoán chỉ ghi siêu dữ liệu kỹ thuật. Không ghi nhận câu nói, số tiền, số tài khoản hay bản ghi âm thô.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // 1. Hardware, OS, Permission & Audio Route
              _DiagSectionCard(
                key: const Key('voice_diag_device_card'),
                title: 'Thiết bị, Quyền & Đường âm thanh',
                icon: Icons.smartphone_rounded,
                rows: [
                  _DiagRow(
                    'Android SDK',
                    diag.androidSdkInt > 0
                        ? 'API ${diag.androidSdkInt}'
                        : 'Không phải Android',
                  ),
                  _DiagRow(
                    'Hãng / Thiết bị',
                    '${diag.manufacturer} · ${diag.model}',
                  ),
                  _DiagRow(
                    'Quyền Micro',
                    diag.hasMicPermission ? 'Đã cấp' : 'Chưa cấp',
                  ),
                  _DiagRow(
                    'Khóa riêng tư Micro OS',
                    diag.isMicPrivacyBlocked == null
                        ? 'Không xác định'
                        : (diag.isMicPrivacyBlocked!
                              ? 'Đang bật khóa'
                              : 'Đang mở'),
                  ),
                  _DiagRow('Đường âm thanh', diag.currentAudioRoute.labelVi),
                  _DiagRow('Hỗ trợ tiếng Việt', diag.vietnameseSupportStatus),
                  _DiagRow(
                    'Engine khả dụng',
                    diag.availableEngines.isEmpty
                        ? 'Chưa phát hiện'
                        : diag.availableEngines.join(', '),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // 2. Active Session State Machine & Monotonic Latencies
              _DiagSectionCard(
                key: const Key('voice_diag_session_card'),
                title: 'Trạng thái Phiên & Độ trễ (Monotonic)',
                icon: Icons.timeline_rounded,
                rows: [
                  _DiagRow('Active Session ID', diag.activeSessionId ?? '—'),
                  _DiagRow('Engine Attempt ID', '${diag.activeAttemptId}'),
                  _DiagRow('Trạng thái FSM', diag.currentPhase.wireValue),
                  _DiagRow(
                    'Mã lỗi gần nhất',
                    diag.lastErrorCode ??
                        diag.lastErrorKind?.name ??
                        'Không có',
                  ),
                  _DiagRow(
                    'Time to Ready',
                    diag.timeToReadyMs != null
                        ? '${diag.timeToReadyMs} ms'
                        : '—',
                  ),
                  _DiagRow(
                    'Time to First Partial',
                    diag.timeToFirstPartialMs != null
                        ? '${diag.timeToFirstPartialMs} ms'
                        : '—',
                  ),
                  _DiagRow(
                    'Time to Final',
                    diag.timeToFinalMs != null
                        ? '${diag.timeToFinalMs} ms'
                        : '—',
                  ),
                  _DiagRow(
                    'Retry / Fallback',
                    '${diag.retryCount} / ${diag.fallbackCount}',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // 3. Engine Mode, Endpoint Policy & Microphone Self-Test
              _DiagCardShell(
                title: 'Chế độ Nhận diện & Kiểm tra Micro',
                icon: Icons.tune_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Chế độ ưu tiên nhận diện',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: VoiceRecognitionPreference.values.map((pref) {
                        final selected = state.activePreference == pref;
                        return ChoiceChip(
                          key: Key('voice_diag_pref_${pref.wireValue}'),
                          label: Text(pref.labelVi),
                          selected: selected,
                          onSelected: (_) {
                            context.read<VoiceAssistantBloc>().add(
                              VoicePreferenceChanged(pref),
                            );
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SwitchListTile.adaptive(
                      key: const Key('voice_diag_auto_endpoint_switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tự dừng thông minh (thử nghiệm)'),
                      subtitle: const Text(
                        'Mặc định tắt để ưu tiên bấm dừng chủ động, tránh cắt giữa câu.',
                      ),
                      value:
                          state.endpointMode ==
                          VoiceEndpointMode.smartAutoEndpoint,
                      onChanged: (enabled) {
                        context.read<VoiceAssistantBloc>().add(
                          VoiceEndpointModeChanged(
                            enabled
                                ? VoiceEndpointMode.smartAutoEndpoint
                                : VoiceEndpointMode.explicitStopOnly,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          key: const Key('voice_diag_mic_selftest_btn'),
                          onPressed: _runningSelfTest
                              ? null
                              : _runMicrophoneSelfTest,
                          icon: _runningSelfTest
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.mic_external_on_rounded),
                          label: Text(
                            _runningSelfTest
                                ? 'Đang kiểm tra Micro...'
                                : 'Kiểm tra Microphone',
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const Key('voice_diag_reset_caps_btn'),
                          onPressed: () {
                            context.read<VoiceAssistantBloc>().add(
                              const VoiceCapabilitiesResetRequested(),
                            );
                          },
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Xóa bộ nhớ Engine'),
                        ),
                        FilledButton.icon(
                          key: const Key('voice_diag_export_btn'),
                          onPressed: () => _copySanitizedReport(diag),
                          icon: const Icon(Icons.ios_share_rounded),
                          label: const Text('Xuất báo cáo ẩn PII'),
                        ),
                      ],
                    ),
                    if (_selfTestResult != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        key: const Key('voice_diag_selftest_result'),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: palette.surfaceRaised,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Kết quả tự kiểm tra PCM16: '
                          '${(_selfTestResult!['passed'] == true && _selfTestResult!['hasSignal'] == true) ? "ĐẠT" : "CHƯA ĐẠT"}\n'
                          '• Mở được mic: ${_selfTestResult!['micOpened'] == true ? "Đạt" : "Chưa đạt"}\n'
                          '• Có tín hiệu: ${_selfTestResult!['hasSignal'] == true ? "Đạt" : "Chưa có tín hiệu"}\n'
                          '• Đã nhận được chữ: ${_selfTestResult!['speechRecognized'] == true ? "Đã xác nhận" : "Chưa kiểm tra chữ"}\n'
                          'Peak: ${_selfTestResult!['peakDbfs'] ?? '—'} dBFS · '
                          'Route: ${_selfTestResult!['audioRoute'] ?? '—'} · '
                          'Status: ${_selfTestResult!['reason'] ?? _selfTestResult!['errorCode'] ?? 'OK'}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 4. Optional On-Demand Offline ASR Model Manager (Section 12)
              _DiagCardShell(
                key: const Key('voice_diag_models_card'),
                title: 'Quản lý Mô hình Offline (Tải theo nhu cầu)',
                icon: Icons.download_for_offline_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Mô hình không nhúng sẵn vào APK để giữ nhẹ máy. '
                      'Kiểm tra SHA-256 và tách biệt giấy phép runtime với trọng số mô hình.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final model in state.models)
                      _ModelRowTile(
                        model: model,
                        busy: state.isModelOperationBusy,
                        sizeLabel: _formatBytesMb(model.spec.sizeBytes),
                        onDownload: () {
                          context.read<VoiceAssistantBloc>().add(
                            VoiceModelDownloadRequested(model.spec),
                          );
                        },
                        onDelete: () {
                          context.read<VoiceAssistantBloc>().add(
                            VoiceModelDeleteRequested(model.spec.id),
                          );
                        },
                        onRollback: () {
                          context.read<VoiceAssistantBloc>().add(
                            VoiceModelRollbackRequested(model.spec.id),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DiagCardShell extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _DiagCardShell({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final palette = TammySemanticColors.of(context);
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: palette.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _DiagSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_DiagRow> rows;

  const _DiagSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final palette = TammySemanticColors.of(context);
    return _DiagCardShell(
      title: title,
      icon: icon,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 14,
                thickness: 0.7,
                color: palette.border.withValues(alpha: 0.7),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    rows[i].label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 6,
                  child: Text(
                    rows[i].value,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DiagRow {
  final String label;
  final String value;
  const _DiagRow(this.label, this.value);
}

class _ModelRowTile extends StatelessWidget {
  final LocalAsrModelInstallState model;
  final bool busy;
  final String sizeLabel;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onRollback;

  const _ModelRowTile({
    required this.model,
    required this.busy,
    required this.sizeLabel,
    required this.onDownload,
    required this.onDelete,
    required this.onRollback,
  });

  @override
  Widget build(BuildContext context) {
    final palette = TammySemanticColors.of(context);
    final spec = model.spec;
    final isInstalled = model.status == LocalAsrModelStatus.installed;
    final isBlocked = !spec.commercialAllowed;
    final isRuntimeUnavailable = !spec.runtimeIntegrated;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isBlocked
              ? palette.warning.withValues(alpha: 0.5)
              : palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                spec.displayNameVi,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                sizeLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: palette.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Runtime: ${spec.runtimeName} (${spec.runtimeLicenseSpdx}) · '
            'Weights: ${spec.modelLicenseSpdx} · '
            '${spec.supportsStreaming ? "Streaming" : "VAD Chunked (non-streaming)"}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          if (isBlocked) ...[
            const SizedBox(height: 4),
            Text(
              'Bị chặn trong bản thương mại do giấy phép ${spec.modelLicenseSpdx} (chỉ thử nghiệm nghiên cứu).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else if (isRuntimeUnavailable) ...[
            const SizedBox(height: 4),
            Text(
              'Chưa khả dụng trong bản dựng này (chưa nhúng bộ chạy ${spec.runtimeName} gốc). Chế độ Chỉ Offline hiện dùng trực tiếp Android On-Device.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (!isInstalled)
                FilledButton.tonal(
                  key: Key('voice_model_download_${spec.id}'),
                  onPressed: (busy || isBlocked || isRuntimeUnavailable)
                      ? null
                      : onDownload,
                  child: Text(
                    isBlocked
                        ? 'Hạn chế giấy phép'
                        : (isRuntimeUnavailable
                              ? 'Chưa khả dụng'
                              : 'Tải về ($sizeLabel)'),
                  ),
                ),
              if (isInstalled)
                OutlinedButton(
                  key: Key('voice_model_delete_${spec.id}'),
                  onPressed: busy ? null : onDelete,
                  child: const Text('Xóa mô hình'),
                ),
              if (model.hasRollbackBackup)
                TextButton(
                  onPressed: busy ? null : onRollback,
                  child: const Text('Khôi phục bản cũ'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
