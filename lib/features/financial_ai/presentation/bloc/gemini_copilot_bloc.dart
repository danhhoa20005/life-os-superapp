import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/dependency_injection.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/smart_omni_intent_parser.dart';
import '../../data/datasources/gemini_remote_datasource.dart';
import '../../data/repositories/gemini_copilot_repository_impl.dart';
import '../../domain/entities/gemini_copilot_entities.dart';
import '../../domain/repositories/gemini_copilot_repository.dart';

sealed class GeminiCopilotEvent extends Equatable {
  const GeminiCopilotEvent();

  @override
  List<Object?> get props => [];
}

final class GeminiCopilotInitialized extends GeminiCopilotEvent {
  const GeminiCopilotInitialized();
}

final class GeminiConnectionSettingsSaved extends GeminiCopilotEvent {
  final String? newApiKey;
  final bool? enabled;
  final String? modelId;
  final bool? maskSensitiveInfo;

  const GeminiConnectionSettingsSaved({
    this.newApiKey,
    this.enabled,
    this.modelId,
    this.maskSensitiveInfo,
  });

  @override
  List<Object?> get props => [newApiKey, enabled, modelId, maskSensitiveInfo];
}

final class GeminiConnectionTestRequested extends GeminiCopilotEvent {
  final String? candidateApiKey;
  final String? modelId;

  const GeminiConnectionTestRequested({this.candidateApiKey, this.modelId});

  @override
  List<Object?> get props => [candidateApiKey, modelId];
}

final class GeminiConnectionDisconnected extends GeminiCopilotEvent {
  const GeminiConnectionDisconnected();
}

final class GeminiOmniAnalyzeRequested extends GeminiCopilotEvent {
  final String rawInput;
  final GeminiContextSnapshot? contextSnapshot;
  final DateTime? referenceTime;

  const GeminiOmniAnalyzeRequested({
    required this.rawInput,
    this.contextSnapshot,
    this.referenceTime,
  });

  @override
  List<Object?> get props => [rawInput, contextSnapshot, referenceTime];
}

final class GeminiOmniDraftDismissed extends GeminiCopilotEvent {
  final String draftId;
  const GeminiOmniDraftDismissed(this.draftId);

  @override
  List<Object?> get props => [draftId];
}

final class GeminiOmniReset extends GeminiCopilotEvent {
  const GeminiOmniReset();
}

enum GeminiCopilotStatus {
  initial,
  ready,
  verifyingConnection,
  analyzing,
}

final class GeminiCopilotState extends Equatable {
  final GeminiCopilotStatus status;
  final GeminiConnectionConfig config;
  final GeminiHybridAnalysisResult? lastResult;
  final Failure? failure;
  final String? feedbackMessage;

  const GeminiCopilotState({
    this.status = GeminiCopilotStatus.initial,
    this.config = const GeminiConnectionConfig(),
    this.lastResult,
    this.failure,
    this.feedbackMessage,
  });

  List<OmniActionDraft> get activeOmniDrafts =>
      lastResult?.actionDrafts ?? const <OmniActionDraft>[];

  GeminiCopilotState copyWith({
    GeminiCopilotStatus? status,
    GeminiConnectionConfig? config,
    GeminiHybridAnalysisResult? lastResult,
    bool clearResult = false,
    Failure? failure,
    bool clearFailure = false,
    String? feedbackMessage,
    bool clearFeedback = false,
  }) {
    return GeminiCopilotState(
      status: status ?? this.status,
      config: config ?? this.config,
      lastResult: clearResult ? null : (lastResult ?? this.lastResult),
      failure: clearFailure ? null : (failure ?? this.failure),
      feedbackMessage: clearFeedback
          ? null
          : (feedbackMessage ?? this.feedbackMessage),
    );
  }

  @override
  List<Object?> get props => [
    status,
    config,
    lastResult,
    failure,
    feedbackMessage,
  ];
}

/// Event-driven BLoC (`0%` Cubit) managing opt-in Gemini AI connection,
/// hardware-keystore API key lifecycle, and Hybrid Offline + Gemini multi-domain analysis.
class GeminiCopilotBloc extends Bloc<GeminiCopilotEvent, GeminiCopilotState> {
  final GeminiCopilotRepository _repository;

  GeminiCopilotBloc({required GeminiCopilotRepository repository})
    : _repository = repository,
      super(const GeminiCopilotState()) {
    on<GeminiCopilotInitialized>(_onInitialized, transformer: sequential());
    on<GeminiConnectionSettingsSaved>(
      _onSettingsSaved,
      transformer: sequential(),
    );
    on<GeminiConnectionTestRequested>(
      _onTestConnection,
      transformer: droppable(),
    );
    on<GeminiConnectionDisconnected>(
      _onDisconnected,
      transformer: sequential(),
    );
    on<GeminiOmniAnalyzeRequested>(_onAnalyze, transformer: restartable());
    on<GeminiOmniDraftDismissed>(_onDraftDismissed, transformer: sequential());
    on<GeminiOmniReset>(_onReset, transformer: sequential());
  }

  Future<void> _onInitialized(
    GeminiCopilotInitialized event,
    Emitter<GeminiCopilotState> emit,
  ) async {
    final res = await _repository.loadConfig();
    res.fold(
      (f) => emit(
        state.copyWith(status: GeminiCopilotStatus.ready, failure: f),
      ),
      (cfg) => emit(
        state.copyWith(
          status: GeminiCopilotStatus.ready,
          config: cfg,
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onSettingsSaved(
    GeminiConnectionSettingsSaved event,
    Emitter<GeminiCopilotState> emit,
  ) async {
    final res = await _repository.saveConnectionSettings(
      newApiKey: event.newApiKey,
      enabled: event.enabled,
      modelId: event.modelId,
      maskSensitiveInfo: event.maskSensitiveInfo,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (cfg) => emit(
        state.copyWith(
          config: cfg,
          clearFailure: true,
          feedbackMessage: event.newApiKey != null &&
                  event.newApiKey!.trim().isNotEmpty
              ? 'Đã mã hóa và lưu khóa kết nối Gemini trên thiết bị.'
              : 'Đã cập nhật tùy chọn Gemini AI.',
        ),
      ),
    );
  }

  Future<void> _onTestConnection(
    GeminiConnectionTestRequested event,
    Emitter<GeminiCopilotState> emit,
  ) async {
    emit(
      state.copyWith(
        status: GeminiCopilotStatus.verifyingConnection,
        clearFailure: true,
        clearFeedback: true,
      ),
    );

    final testRes = await _repository.verifyConnection(
      candidateApiKey: event.candidateApiKey,
      modelId: event.modelId,
    );
    final cfgRes = await _repository.loadConfig();
    final latestCfg = cfgRes.fold((_) => state.config, (c) => c);

    testRes.fold(
      (f) => emit(
        state.copyWith(
          status: GeminiCopilotStatus.ready,
          config: latestCfg,
          failure: f,
        ),
      ),
      (msg) => emit(
        state.copyWith(
          status: GeminiCopilotStatus.ready,
          config: latestCfg,
          clearFailure: true,
          feedbackMessage: msg,
        ),
      ),
    );
  }

  Future<void> _onDisconnected(
    GeminiConnectionDisconnected event,
    Emitter<GeminiCopilotState> emit,
  ) async {
    final res = await _repository.disconnectAndClearKey();
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (cfg) => emit(
        state.copyWith(
          status: GeminiCopilotStatus.ready,
          config: cfg,
          clearResult: true,
          clearFailure: true,
          feedbackMessage:
              'Đã ngắt kết nối Gemini và xóa khóa khỏi bộ nhớ bảo mật.',
        ),
      ),
    );
  }

  Future<void> _onAnalyze(
    GeminiOmniAnalyzeRequested event,
    Emitter<GeminiCopilotState> emit,
  ) async {
    emit(
      state.copyWith(
        status: GeminiCopilotStatus.analyzing,
        clearFailure: true,
        clearFeedback: true,
      ),
    );

    final res = await _repository.analyzeHybridOmniCommand(
      rawInput: event.rawInput,
      contextSnapshot: event.contextSnapshot,
      referenceTime: event.referenceTime,
    );

    res.fold(
      (f) => emit(
        state.copyWith(status: GeminiCopilotStatus.ready, failure: f),
      ),
      (hybrid) => emit(
        state.copyWith(
          status: GeminiCopilotStatus.ready,
          lastResult: hybrid,
          clearFailure: true,
          feedbackMessage: hybrid.fallbackNoticeVi,
        ),
      ),
    );
  }

  void _onDraftDismissed(
    GeminiOmniDraftDismissed event,
    Emitter<GeminiCopilotState> emit,
  ) {
    final current = state.lastResult;
    if (current == null) return;
    final remaining = current.actionDrafts
        .where((d) => d.id != event.draftId)
        .toList(growable: false);
    emit(
      state.copyWith(
        lastResult: current.copyWith(actionDrafts: remaining),
        clearFailure: true,
        clearFeedback: true,
      ),
    );
  }

  void _onReset(GeminiOmniReset event, Emitter<GeminiCopilotState> emit) {
    emit(
      state.copyWith(
        status: GeminiCopilotStatus.ready,
        clearResult: true,
        clearFailure: true,
        clearFeedback: true,
      ),
    );
  }
}

/// Ensures a `GeminiCopilotBloc` is available in [context], reusing the ancestor provider
/// when inside the main app shell or creating a scoped fallback in isolated widget tests.
class EnsureGeminiCopilotScope extends StatelessWidget {
  final Widget child;
  const EnsureGeminiCopilotScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    try {
      context.read<GeminiCopilotBloc>();
      return child;
    } catch (_) {
      return BlocProvider<GeminiCopilotBloc>(
        create: (_) {
          final bloc = sl.isRegistered<GeminiCopilotBloc>()
              ? sl<GeminiCopilotBloc>()
              : GeminiCopilotBloc(
                  repository: GeminiCopilotRepositoryImpl(
                    GeminiRemoteDataSource(),
                  ),
                );
          return bloc..add(const GeminiCopilotInitialized());
        },
        child: child,
      );
    }
  }
}
