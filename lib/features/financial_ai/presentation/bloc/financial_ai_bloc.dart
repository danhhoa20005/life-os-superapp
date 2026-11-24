import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../domain/entities/financial_ai_entities.dart';
import '../../domain/repositories/financial_ai_repository.dart';
import '../../domain/usecases/financial_ai_usecases.dart';

sealed class FinancialAiEvent extends Equatable {
  const FinancialAiEvent();

  @override
  List<Object?> get props => [];
}

final class FinancialAiInitialized extends FinancialAiEvent {
  final String userId;
  const FinancialAiInitialized(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class FinancialTextSubmitted extends FinancialAiEvent {
  final String userId;
  final String text;
  final FinancialInputSource source;
  final String? preferredWalletId;
  final String? familyId;
  final DateTime? referenceTime;
  final List<WalletEntity>? knownWallets;
  final List<CategoryEntity>? knownCategories;

  const FinancialTextSubmitted({
    required this.userId,
    required this.text,
    this.source = FinancialInputSource.manualText,
    this.preferredWalletId,
    this.familyId,
    this.referenceTime,
    this.knownWallets,
    this.knownCategories,
  });

  @override
  List<Object?> get props => [
    userId,
    text,
    source,
    preferredWalletId,
    familyId,
    referenceTime,
  ];
}

final class FinancialCandidateUpdated extends FinancialAiEvent {
  final TransactionCandidate updatedCandidate;
  const FinancialCandidateUpdated(this.updatedCandidate);

  @override
  List<Object?> get props => [updatedCandidate];
}

final class FinancialCategoryCorrected extends FinancialAiEvent {
  final String userId;
  final String draftId;
  final String selectedCategoryId;
  final String selectedCategoryName;
  final bool learnRuleForMerchant;

  const FinancialCategoryCorrected({
    required this.userId,
    required this.draftId,
    required this.selectedCategoryId,
    required this.selectedCategoryName,
    this.learnRuleForMerchant = true,
  });

  @override
  List<Object?> get props => [
    userId,
    draftId,
    selectedCategoryId,
    selectedCategoryName,
    learnRuleForMerchant,
  ];
}

final class FinancialDraftConfirmed extends FinancialAiEvent {
  final String userId;
  final String? draftId; // If null, confirms all ready drafts in current analysis

  const FinancialDraftConfirmed({required this.userId, this.draftId});

  @override
  List<Object?> get props => [userId, draftId];
}

final class FinancialDraftRejected extends FinancialAiEvent {
  final String userId;
  final String draftId;

  const FinancialDraftRejected({required this.userId, required this.draftId});

  @override
  List<Object?> get props => [userId, draftId];
}

final class FinancialAiPreferencesUpdated extends FinancialAiEvent {
  final UserAiClassificationPreferences preferences;
  const FinancialAiPreferencesUpdated(this.preferences);

  @override
  List<Object?> get props => [preferences];
}

final class FinancialPersonalizationRuleDeleted extends FinancialAiEvent {
  final String userId;
  final String ruleId;

  const FinancialPersonalizationRuleDeleted({
    required this.userId,
    required this.ruleId,
  });

  @override
  List<Object?> get props => [userId, ruleId];
}

final class FinancialPersonalizationCleared extends FinancialAiEvent {
  final String userId;
  const FinancialPersonalizationCleared(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class FinancialAiReset extends FinancialAiEvent {
  const FinancialAiReset();
}

enum FinancialAiStatus {
  initial,
  loading,
  ready,
  analyzing,
  reviewRequired,
  failure,
}

final class FinancialAiState extends Equatable {
  final FinancialAiStatus status;
  final FinancialModelMetadata modelMetadata;
  final FinancialAnalysisResult? currentAnalysis;
  final List<TransactionCandidate> activeCandidates;
  final List<TransactionCandidate> pendingDrafts;
  final List<PersonalizationRule> personalizationRules;
  final UserAiClassificationPreferences? preferences;
  final bool isConfirming;
  final Failure? failure;
  final String? feedbackMessage;

  const FinancialAiState({
    this.status = FinancialAiStatus.initial,
    this.modelMetadata = FinancialModelMetadata.fallbackMetadata,
    this.currentAnalysis,
    this.activeCandidates = const [],
    this.pendingDrafts = const [],
    this.personalizationRules = const [],
    this.preferences,
    this.isConfirming = false,
    this.failure,
    this.feedbackMessage,
  });

  FinancialAiState copyWith({
    FinancialAiStatus? status,
    FinancialModelMetadata? modelMetadata,
    FinancialAnalysisResult? currentAnalysis,
    bool clearAnalysis = false,
    List<TransactionCandidate>? activeCandidates,
    List<TransactionCandidate>? pendingDrafts,
    List<PersonalizationRule>? personalizationRules,
    UserAiClassificationPreferences? preferences,
    bool? isConfirming,
    Failure? failure,
    bool clearFailure = false,
    String? feedbackMessage,
    bool clearFeedback = false,
  }) {
    return FinancialAiState(
      status: status ?? this.status,
      modelMetadata: modelMetadata ?? this.modelMetadata,
      currentAnalysis: clearAnalysis
          ? null
          : (currentAnalysis ?? this.currentAnalysis),
      activeCandidates: activeCandidates != null
          ? List.unmodifiable(activeCandidates)
          : this.activeCandidates,
      pendingDrafts: pendingDrafts != null
          ? List.unmodifiable(pendingDrafts)
          : this.pendingDrafts,
      personalizationRules: personalizationRules != null
          ? List.unmodifiable(personalizationRules)
          : this.personalizationRules,
      preferences: preferences ?? this.preferences,
      isConfirming: isConfirming ?? this.isConfirming,
      failure: clearFailure ? null : (failure ?? this.failure),
      feedbackMessage: clearFeedback
          ? null
          : (feedbackMessage ?? this.feedbackMessage),
    );
  }

  @override
  List<Object?> get props => [
    status,
    modelMetadata,
    currentAnalysis,
    activeCandidates,
    pendingDrafts,
    personalizationRules,
    preferences,
    isConfirming,
    failure,
    feedbackMessage,
  ];
}

/// Phase 14 — Event-driven FinancialAiBloc (`0%` Cubit):
/// - `restartable()` on `FinancialTextSubmitted` cancels stale analyses when new text arrives.
/// - `droppable()` on `FinancialDraftConfirmed` prevents duplicate ledger writes on rapid double-taps.
class FinancialAiBloc extends Bloc<FinancialAiEvent, FinancialAiState> {
  final FinancialAiRepository _repository;
  final AnalyzeFinancialTextUseCase _analyzeText;
  final ConfirmTransactionDraftUseCase _confirmDraft;
  final SaveCategoryCorrectionUseCase _saveCorrection;
  final GetPendingTransactionsUseCase _getPendingDrafts;

  FinancialAiBloc({
    required FinancialAiRepository repository,
    required AnalyzeFinancialTextUseCase analyzeText,
    required ConfirmTransactionDraftUseCase confirmDraft,
    required SaveCategoryCorrectionUseCase saveCorrection,
    required GetPendingTransactionsUseCase getPendingDrafts,
  }) : _repository = repository,
       _analyzeText = analyzeText,
       _confirmDraft = confirmDraft,
       _saveCorrection = saveCorrection,
       _getPendingDrafts = getPendingDrafts,
       super(
         FinancialAiState(modelMetadata: repository.currentModelMetadata),
       ) {
    on<FinancialAiInitialized>(_onInitialized, transformer: restartable());
    on<FinancialTextSubmitted>(_onTextSubmitted, transformer: restartable());
    on<FinancialCandidateUpdated>(
      _onCandidateUpdated,
      transformer: sequential(),
    );
    on<FinancialCategoryCorrected>(
      _onCategoryCorrected,
      transformer: sequential(),
    );
    on<FinancialDraftConfirmed>(_onDraftConfirmed, transformer: droppable());
    on<FinancialDraftRejected>(_onDraftRejected, transformer: sequential());
    on<FinancialAiPreferencesUpdated>(
      _onPreferencesUpdated,
      transformer: sequential(),
    );
    on<FinancialPersonalizationRuleDeleted>(
      _onRuleDeleted,
      transformer: sequential(),
    );
    on<FinancialPersonalizationCleared>(
      _onPersonalizationCleared,
      transformer: sequential(),
    );
    on<FinancialAiReset>(_onReset, transformer: sequential());
  }

  Future<void> _onInitialized(
    FinancialAiInitialized event,
    Emitter<FinancialAiState> emit,
  ) async {
    emit(state.copyWith(status: FinancialAiStatus.loading, clearFailure: true));
    final initRes = await _repository.initializeEngine();
    initRes.fold(
      (f) => emit(
        state.copyWith(
          status: FinancialAiStatus.ready,
          modelMetadata: _repository.currentModelMetadata,
          failure: f,
        ),
      ),
      (meta) => emit(
        state.copyWith(status: FinancialAiStatus.ready, modelMetadata: meta),
      ),
    );

    await Future.wait([
      emit.forEach(
        _repository.watchPreferences(event.userId),
        onData: (res) => res.fold(
          (_) => state,
          (prefs) => state.copyWith(preferences: prefs),
        ),
      ),
      emit.forEach(
        _repository.watchPersonalizationRules(event.userId),
        onData: (res) => res.fold(
          (_) => state,
          (rules) => state.copyWith(personalizationRules: rules),
        ),
      ),
      emit.forEach(
        _getPendingDrafts(event.userId),
        onData: (res) => res.fold(
          (_) => state,
          (drafts) => state.copyWith(pendingDrafts: drafts),
        ),
      ),
    ]);
  }

  Future<void> _onTextSubmitted(
    FinancialTextSubmitted event,
    Emitter<FinancialAiState> emit,
  ) async {
    emit(
      state.copyWith(
        status: FinancialAiStatus.analyzing,
        clearFailure: true,
        clearFeedback: true,
      ),
    );

    final res = await _analyzeText(
      AnalyzeFinancialTextParams(
        userId: event.userId,
        text: event.text,
        source: event.source,
        preferredWalletId: event.preferredWalletId,
        familyId: event.familyId,
        referenceTime: event.referenceTime,
        knownWallets: event.knownWallets,
        knownCategories: event.knownCategories,
      ),
    );

    res.fold(
      (failure) => emit(
        state.copyWith(
          status: FinancialAiStatus.failure,
          failure: failure,
        ),
      ),
      (analysis) => emit(
        state.copyWith(
          status: analysis.hasActionableCandidates
              ? FinancialAiStatus.reviewRequired
              : FinancialAiStatus.ready,
          modelMetadata: analysis.modelMetadata,
          currentAnalysis: analysis,
          activeCandidates: analysis.candidates,
          feedbackMessage: analysis.nonTransactionReason,
        ),
      ),
    );
  }

  void _onCandidateUpdated(
    FinancialCandidateUpdated event,
    Emitter<FinancialAiState> emit,
  ) {
    final updated = state.activeCandidates
        .map(
          (c) =>
              c.draftId == event.updatedCandidate.draftId
              ? event.updatedCandidate
              : c,
        )
        .toList(growable: false);
    emit(
      state.copyWith(
        activeCandidates: updated,
        clearFailure: true,
        clearFeedback: true,
      ),
    );
  }

  Future<void> _onCategoryCorrected(
    FinancialCategoryCorrected event,
    Emitter<FinancialAiState> emit,
  ) async {
    final target = state.activeCandidates
        .where((c) => c.draftId == event.draftId)
        .firstOrNull;
    if (target == null) return;

    final updatedList = state.activeCandidates
        .map(
          (c) => c.draftId == event.draftId
              ? c.copyWith(
                  resolvedCategoryId: event.selectedCategoryId,
                  resolvedCategoryName: event.selectedCategoryName,
                )
              : c,
        )
        .toList(growable: false);

    emit(state.copyWith(activeCandidates: updatedList, clearFailure: true));

    if (event.learnRuleForMerchant &&
        target.merchantCanonicalKey != null &&
        target.merchantCanonicalKey!.isNotEmpty) {
      final res = await _saveCorrection(
        SaveCategoryCorrectionParams(
          userId: event.userId,
          merchantDisplay: target.merchant ?? target.description,
          merchantCanonicalKey: target.merchantCanonicalKey!,
          selectedCategoryId: event.selectedCategoryId,
          selectedCategoryName: event.selectedCategoryName,
          semanticKey: target.topPrediction.semanticKey,
          directionCondition: target.transactionType.expectedDirection,
          sourceContext: target.source.name,
        ),
      );
      res.fold(
        (f) => emit(state.copyWith(failure: f)),
        (_) => emit(
          state.copyWith(
            feedbackMessage:
                'Đã ghi nhớ quy tắc "${target.merchant ?? target.description}" → ${event.selectedCategoryName}.',
          ),
        ),
      );
    }
  }

  Future<void> _onDraftConfirmed(
    FinancialDraftConfirmed event,
    Emitter<FinancialAiState> emit,
  ) async {
    if (state.isConfirming) return;
    final toConfirm = event.draftId != null
        ? state.activeCandidates
              .where((c) => c.draftId == event.draftId)
              .toList()
        : List<TransactionCandidate>.from(state.activeCandidates);

    if (toConfirm.isEmpty) return;

    emit(
      state.copyWith(
        isConfirming: true,
        clearFailure: true,
        clearFeedback: true,
      ),
    );

    final remaining = List<TransactionCandidate>.from(state.activeCandidates);
    var savedCount = 0;
    Failure? firstError;

    for (final draft in toConfirm) {
      final res = await _confirmDraft(
        ConfirmTransactionDraftParams(userId: event.userId, candidate: draft),
      );
      res.fold(
        (f) => firstError ??= f,
        (_) {
          savedCount++;
          remaining.removeWhere((x) => x.draftId == draft.draftId);
        },
      );
    }

    if (firstError != null) {
      emit(
        state.copyWith(
          isConfirming: false,
          activeCandidates: remaining,
          failure: firstError,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        isConfirming: false,
        status: remaining.isEmpty
            ? FinancialAiStatus.ready
            : FinancialAiStatus.reviewRequired,
        activeCandidates: remaining,
        clearAnalysis: remaining.isEmpty,
        feedbackMessage:
            'Đã xác nhận và ghi sổ an toàn $savedCount giao dịch.',
      ),
    );
  }

  Future<void> _onDraftRejected(
    FinancialDraftRejected event,
    Emitter<FinancialAiState> emit,
  ) async {
    final remaining = state.activeCandidates
        .where((c) => c.draftId != event.draftId)
        .toList(growable: false);
    await _repository.deletePendingDraft(
      userId: event.userId,
      draftId: event.draftId,
    );
    emit(
      state.copyWith(
        status: remaining.isEmpty
            ? FinancialAiStatus.ready
            : FinancialAiStatus.reviewRequired,
        activeCandidates: remaining,
        clearAnalysis: remaining.isEmpty,
        feedbackMessage: 'Đã bỏ qua bản nháp giao dịch.',
      ),
    );
  }

  Future<void> _onPreferencesUpdated(
    FinancialAiPreferencesUpdated event,
    Emitter<FinancialAiState> emit,
  ) async {
    final res = await _repository.updatePreferences(event.preferences);
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          preferences: event.preferences,
          feedbackMessage: 'Đã lưu cài đặt AI phân loại tài chính.',
        ),
      ),
    );
  }

  Future<void> _onRuleDeleted(
    FinancialPersonalizationRuleDeleted event,
    Emitter<FinancialAiState> emit,
  ) async {
    final res = await _repository.deletePersonalizationRule(
      userId: event.userId,
      ruleId: event.ruleId,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(feedbackMessage: 'Đã xóa quy tắc cá nhân hóa.')),
    );
  }

  Future<void> _onPersonalizationCleared(
    FinancialPersonalizationCleared event,
    Emitter<FinancialAiState> emit,
  ) async {
    final res = await _repository.clearAllPersonalizationData(event.userId);
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          personalizationRules: const [],
          feedbackMessage: 'Đã xóa toàn bộ dữ liệu cá nhân hóa AI trên thiết bị.',
        ),
      ),
    );
  }

  void _onReset(FinancialAiReset event, Emitter<FinancialAiState> emit) {
    emit(
      state.copyWith(
        status: FinancialAiStatus.ready,
        clearAnalysis: true,
        activeCandidates: const [],
        clearFailure: true,
        clearFeedback: true,
      ),
    );
  }
}
