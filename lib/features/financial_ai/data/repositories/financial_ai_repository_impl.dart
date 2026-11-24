import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../domain/entities/financial_ai_entities.dart';
import '../../domain/repositories/financial_ai_repository.dart';
import '../../domain/services/financial_classifier.dart';
import '../datasources/financial_ai_local_sync_datasource.dart';
import '../extraction/financial_entity_extractor.dart';
import '../inference/rule_based_classifier.dart';
import '../inference/taxonomy_catalog.dart';
import '../normalization/financial_text_normalizer.dart';
import '../personalization/confidence_policy_engine.dart';

class FinancialAiRepositoryImpl implements FinancialAiRepository {
  final FinancialClassifier _classifier;
  final RuleBasedClassifier _ruleFallback;
  final FinancialTextNormalizer _normalizer;
  final FinancialEntityExtractor _extractor;
  final FinancialAiLocalSyncDataSource _localSync;
  final TransactionRepository _transactionRepository;
  final FirebaseFirestore _firestore;
  static const Uuid _uuid = Uuid();

  FinancialAiRepositoryImpl({
    required FinancialClassifier classifier,
    RuleBasedClassifier? ruleFallback,
    required FinancialTextNormalizer normalizer,
    required FinancialEntityExtractor extractor,
    required FinancialAiLocalSyncDataSource localSync,
    required TransactionRepository transactionRepository,
    required FirebaseFirestore firestore,
  }) : _classifier = classifier,
       _ruleFallback = ruleFallback ?? RuleBasedClassifier(),
       _normalizer = normalizer,
       _extractor = extractor,
       _localSync = localSync,
       _transactionRepository = transactionRepository,
       _firestore = firestore;

  @override
  FinancialModelMetadata get currentModelMetadata => _classifier.metadata;

  @override
  Future<Result<FinancialModelMetadata>> initializeEngine() async {
    try {
      await _classifier.initialize();
      return Success(_classifier.metadata);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<ExtractedFinancialEntity>>> extractEntities({
    required String text,
    DateTime? referenceTime,
  }) async {
    try {
      return Success(
        _extractor.extractAll(text, referenceTime: referenceTime),
      );
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<ClassificationResult>> classifyNormalizedSegment(
    String normalizedText,
  ) async {
    try {
      final res = await _classifier.classify(normalizedText);
      return Success(res);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  Future<List<CategoryEntity>> _loadUserCategories(
    String userId,
    List<CategoryEntity>? provided,
  ) async {
    if (provided != null && provided.isNotEmpty) return provided;
    try {
      final res = await _transactionRepository.watchCategories(userId).first;
      final list = res.fold<List<CategoryEntity>>(
        (_) => const [],
        (items) => items,
      );
      if (list.isNotEmpty) return list;
    } catch (_) {}
    try {
      final snap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('categories')
          .get();
      return snap.docs.map((doc) {
        final d = doc.data();
        return CategoryEntity(
          id: (d['id'] as String?) ?? doc.id,
          ownerId: (d['ownerId'] as String?) ?? userId,
          name: (d['name'] as String?) ?? '',
          direction: (d['direction'] as String?) ?? 'debit',
          iconKey: (d['iconKey'] as String?) ?? 'category',
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<WalletEntity>> _loadUserWallets(
    String userId,
    List<WalletEntity>? provided,
  ) async {
    if (provided != null && provided.isNotEmpty) return provided;
    try {
      final res = await _transactionRepository.watchWallets(userId).first;
      final list = res.fold<List<WalletEntity>>(
        (_) => const [],
        (items) => items,
      );
      if (list.isNotEmpty) return list;
    } catch (_) {}
    try {
      final snap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('wallets')
          .get();
      return snap.docs.map((doc) {
        final d = doc.data();
        final rawType = (d['type'] as String?) ?? 'cash';
        final type = switch (rawType) {
          'bank' => WalletType.bank,
          'creditCard' || 'credit_card' => WalletType.creditCard,
          'savings' || 'investment' => WalletType.savings,
          _ => WalletType.cash,
        };
        return WalletEntity(
          id: (d['id'] as String?) ?? doc.id,
          ownerId: (d['ownerId'] as String?) ?? userId,
          name: (d['name'] as String?) ?? 'Ví',
          type: type,
          bankCode: d['bankCode'] as String?,
          maskedAccount: d['maskedAccount'] as String?,
          balanceMinor: (d['balanceMinor'] as num?)?.toInt() ?? 0,
          isEstimatedBalance: (d['isEstimatedBalance'] as bool?) ?? true,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<Result<ResolvedCategoryMatch>> resolveUserCategory({
    required String userId,
    required String semanticKey,
    required String direction,
    String? merchantCanonicalKey,
    FinancialInputSource source = FinancialInputSource.manualText,
    int? amountMinor,
    List<CategoryEntity>? knownCategories,
  }) async {
    try {
      final categories = await _loadUserCategories(userId, knownCategories);
      final prefs = await _localSync.getPreferences(userId);

      // 1. Check active PersonalizationRule ONLY if its target categoryId still exists in user's categories!
      if (prefs.personalizationEnabled &&
          merchantCanonicalKey != null &&
          merchantCanonicalKey.isNotEmpty) {
        final rules = await _localSync.getRulesForUser(userId);
        for (final rule in rules) {
          if (rule.matchesContext(
            canonicalKey: merchantCanonicalKey,
            direction: direction,
            source: source,
            amountMinor: amountMinor,
          )) {
            final matchingCat = categories
                .where((c) => c.id == rule.selectedCategoryId)
                .firstOrNull;
            if (matchingCat != null) {
              return Success(
                ResolvedCategoryMatch(
                  categoryId: matchingCat.id,
                  displayCategoryName: matchingCat.name,
                  suggestedCategoryName: matchingCat.name,
                  semanticKey: rule.semanticKey,
                  hasExactUserCategory: true,
                ),
              );
            }
          }
        }
      }

      // 2. Dynamic semantic -> user category mapping
      final resolved = FinancialTaxonomyCatalog.resolveAgainstUserCategories(
        semanticKey: semanticKey,
        direction: direction,
        userCategories: categories,
      );
      return Success(resolved);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  String? _resolveWalletHint(
    String? hint,
    List<WalletEntity> wallets, {
    String? excludeWalletId,
  }) {
    if (hint == null || hint.isEmpty || wallets.isEmpty) return null;
    final candidates = wallets
        .where((w) => w.id != excludeWalletId)
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    if (hint == 'CASH') {
      return candidates
          .where((w) => w.type == WalletType.cash)
          .firstOrNull
          ?.id;
    }
    if (hint == 'SAVINGS') {
      return candidates
          .where((w) => w.type == WalletType.savings)
          .firstOrNull
          ?.id;
    }
    if (hint == 'BANK') {
      final banks = candidates.where((w) => w.type == WalletType.bank).toList();
      // Only auto-pick if unambiguous (single bank wallet)
      return banks.length == 1 ? banks.single.id : null;
    }

    final upperHint = hint.toUpperCase();
    // 1. Exact bankCode match first (prevents 'MB' from matching substring inside 'VIETCOMBANK'!)
    final byExactCode = candidates.where((w) {
      return (w.bankCode ?? '').trim().toUpperCase() == upperHint;
    }).toList();
    if (byExactCode.length == 1) {
      return byExactCode.single.id;
    }

    // 2. Word-boundary / bank-prefix match on wallet name (e.g. 'MBBANK', 'MB lương')
    final boundaryPattern = RegExp(
      '(?:^|\\s)${RegExp.escape(upperHint)}(?:\\b|BANK)',
    );
    final byNameBoundary = candidates.where((w) {
      return boundaryPattern.hasMatch(w.name.toUpperCase());
    }).toList();
    return byNameBoundary.length == 1 ? byNameBoundary.single.id : null;
  }

  @override
  Future<Result<({bool isDuplicate, String? matchedTransactionId})>>
  detectDuplicate({
    required String userId,
    required String fingerprint,
    required String direction,
    required int amountMinor,
    required DateTime occurredAt,
    String? referenceCode,
  }) async {
    try {
      final softFps =
          BankNotificationParser.computeOverlappingSoftWindowFingerprints(
            ownerId: userId,
            direction: direction,
            amountMinor: amountMinor,
            occurredAt: occurredAt,
          );
      final col = _firestore
          .collection('users')
          .doc(userId)
          .collection('transactions');

      final exactSnap = await col
          .where('crossSourceFingerprint', isEqualTo: fingerprint)
          .limit(3)
          .get();
      for (final doc in exactSnap.docs) {
        if (doc.data()['verification'] != 'rejected') {
          return Success((isDuplicate: true, matchedTransactionId: doc.id));
        }
      }

      if (softFps.isNotEmpty) {
        final softSnap = await col
            .where('softWindowFingerprint', whereIn: softFps)
            .limit(5)
            .get();
        for (final doc in softSnap.docs) {
          final d = doc.data();
          if (d['verification'] == 'rejected') continue;
          final existingRef = (d['referenceCode'] as String?)?.trim() ?? '';
          final incomingRef = (referenceCode ?? '').trim();
          if (existingRef.isNotEmpty &&
              incomingRef.isNotEmpty &&
              existingRef.toUpperCase() != incomingRef.toUpperCase()) {
            continue;
          }
          return Success((isDuplicate: true, matchedTransactionId: doc.id));
        }
      }

      return const Success((isDuplicate: false, matchedTransactionId: null));
    } catch (_) {
      return const Success((isDuplicate: false, matchedTransactionId: null));
    }
  }

  @override
  Future<Result<FinancialAnalysisResult>> analyzeText({
    required String userId,
    required String text,
    FinancialInputSource source = FinancialInputSource.manualText,
    String? preferredWalletId,
    String? familyId,
    DateTime? referenceTime,
    String? externalReferenceId,
    List<WalletEntity>? knownWallets,
    List<CategoryEntity>? knownCategories,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final refTime = referenceTime ?? _normalizer.currentReferenceTime();
      final normalizedFull = _normalizer.normalizeText(text);
      final req = FinancialAnalysisRequest(
        requestId: _uuid.v4(),
        userId: userId,
        originalText: OtpRedactor.redact(text),
        normalizedText: normalizedFull,
        source: source,
        referenceTime: refTime,
        timezoneOffsetMinutes: refTime.timeZoneOffset.inMinutes,
        preferredWalletId: preferredWalletId,
        familyId: familyId,
        externalReferenceId: externalReferenceId,
      );

      // Stage 1: Non-transaction / OTP / Balance / Negation / Cancellation guard
      final screen = _extractor.screenWholeInput(text);
      if (screen.isBlockedOrNonTransaction) {
        sw.stop();
        return Success(
          FinancialAnalysisResult(
            request: req,
            candidates: const [],
            nonTransactionReason: screen.explanationVi,
            requiresConfirmation: false,
            modelMetadata: _classifier.metadata,
            totalElapsedMicros: sw.elapsedMicroseconds,
          ),
        );
      }

      // Stage 2: Extract & segment 1..N financial clauses
      final extractedList = _extractor.extractAll(
        text,
        referenceTime: refTime,
      );
      if (extractedList.isEmpty) {
        sw.stop();
        return Success(
          FinancialAnalysisResult(
            request: req,
            candidates: const [],
            nonTransactionReason:
                'Chưa tìm thấy thông tin số tiền hoặc nghiệp vụ thu/chi hợp lệ.',
            requiresConfirmation: true,
            modelMetadata: _classifier.metadata,
            totalElapsedMicros: sw.elapsedMicroseconds,
          ),
        );
      }

      final prefs = await _localSync.getPreferences(userId);
      final wallets = await _loadUserWallets(userId, knownWallets);
      final categories = await _loadUserCategories(userId, knownCategories);
      final personalRules = prefs.personalizationEnabled
          ? await _localSync.getRulesForUser(userId)
          : const <PersonalizationRule>[];

      if (prefs.aiClassificationEnabled) {
        await _classifier.initialize();
      } else {
        await _ruleFallback.initialize();
      }

      final candidates = <TransactionCandidate>[];

      for (final ext in extractedList) {
        final flags = List<AmbiguityFlag>.from(ext.ambiguityFlags);
        final direction = ext.transactionType.expectedDirection;

        // Stage 3: Check Personalization Engine first (if category still exists!)
        PersonalizationRule? matchedRule;
        CategoryEntity? matchedRuleCategory;
        if (ext.merchantCanonicalKey != null) {
          for (final rule in personalRules) {
            if (rule.matchesContext(
              canonicalKey: ext.merchantCanonicalKey!,
              direction: direction,
              source: source,
              amountMinor: ext.amountMinor,
            )) {
              final validCat = categories
                  .where((c) => c.id == rule.selectedCategoryId)
                  .firstOrNull;
              if (validCat != null) {
                matchedRule = rule;
                matchedRuleCategory = validCat;
                break;
              }
            }
          }
        }

        // Stage 4: Local Offline AI Category Classification (conditioned on direction!)
        final activeClassifier = prefs.aiClassificationEnabled
            ? _classifier
            : _ruleFallback;
        final rawClassRes = await activeClassifier.classify(
          ext.classifierInput,
        );

        final alignedPreds = _alignPredictionsWithDirection(
          rawPredictions: rawClassRes.predictions,
          direction: direction,
          deterministicSemanticHint: ext.candidateSemanticKey,
        );

        CategoryPrediction topPred;
        List<CategoryPrediction> altPreds;
        if (matchedRule != null && matchedRuleCategory != null) {
          topPred = CategoryPrediction(
            semanticKey: matchedRule.semanticKey,
            suggestedDisplayName: matchedRuleCategory.name,
            probability: matchedRule.ruleConfidence,
            origin: ClassifierInferenceOrigin.personalizationRule,
          );
          altPreds = alignedPreds.take(3).toList(growable: false);
        } else {
          topPred = alignedPreds.first;
          altPreds = alignedPreds.skip(1).take(3).toList(growable: false);
        }

        // Stage 5: Resolve User Category ID safely (NEVER invent missing ID!)
        ResolvedCategoryMatch resolvedCat;
        if (matchedRule != null && matchedRuleCategory != null) {
          resolvedCat = ResolvedCategoryMatch(
            categoryId: matchedRuleCategory.id,
            displayCategoryName: matchedRuleCategory.name,
            suggestedCategoryName: matchedRuleCategory.name,
            semanticKey: matchedRule.semanticKey,
            hasExactUserCategory: true,
          );
        } else {
          resolvedCat = FinancialTaxonomyCatalog.resolveAgainstUserCategories(
            semanticKey: topPred.semanticKey,
            direction: direction == 'credit' ? 'credit' : 'debit',
            userCategories: categories,
          );
        }

        if (ext.transactionType.createsStandardPnlImpact) {
          if (!resolvedCat.hasExactUserCategory && categories.isNotEmpty) {
            flags.add(AmbiguityFlag.unmappedUserCategory);
          }
          if (resolvedCat.hasMultipleMatches) {
            flags.add(AmbiguityFlag.multipleMatchingUserCategories);
          }
          if (topPred.probability < prefs.minAutoSuggestConfidence) {
            flags.add(AmbiguityFlag.lowCategoryConfidence);
          }
        }

        // Stage 6: Resolve Source & Destination Wallets safely (NEVER guess from merchant!)
        String? srcWalletId = _resolveWalletHint(ext.sourceAccountHint, wallets);
        if (srcWalletId == null && ext.sourceAccountHint == null) {
          if (preferredWalletId != null &&
              wallets.any((w) => w.id == preferredWalletId)) {
            srcWalletId = preferredWalletId;
          } else if (wallets.length == 1) {
            srcWalletId = wallets.single.id;
          } else if (wallets.isNotEmpty &&
              source == FinancialInputSource.manualText) {
            srcWalletId = wallets.first.id;
          }
        }
        if (srcWalletId == null) {
          flags.add(AmbiguityFlag.missingSourceWallet);
        }

        String? dstWalletId;
        final needsDstWallet =
            ext.transactionType == FinancialTransactionType.internalTransfer ||
            ext.transactionType == FinancialTransactionType.investmentTransfer;
        if (needsDstWallet) {
          dstWalletId = _resolveWalletHint(
            ext.destinationAccountHint,
            wallets,
            excludeWalletId: srcWalletId,
          );
          if (dstWalletId == null) {
            flags.add(AmbiguityFlag.missingDestinationWalletForTransfer);
          }
        }

        final effectiveDate = ext.explicitOccurredAt ?? refTime;
        final effectiveAmount = ext.amountMinor ?? 0;

        // Stage 7: Duplicate Detection & Fingerprint
        final fpDirection = direction == 'credit' ? 'credit' : 'debit';
        final fingerprint =
            BankNotificationParser.computeCrossSourceFingerprint(
              ownerId: userId,
              direction: fpDirection,
              amountMinor: effectiveAmount,
              occurredAt: effectiveDate,
              referenceCode: externalReferenceId,
            );

        var isDup = false;
        String? dupTxId;
        if (effectiveAmount > 0) {
          final dupRes = await detectDuplicate(
            userId: userId,
            fingerprint: fingerprint,
            direction: fpDirection,
            amountMinor: effectiveAmount,
            occurredAt: effectiveDate,
            referenceCode: externalReferenceId,
          );
          dupRes.fold((_) {}, (d) {
            isDup = d.isDuplicate;
            dupTxId = d.matchedTransactionId;
          });
          if (isDup) {
            flags.add(AmbiguityFlag.potentialDuplicate);
          }
        }

        // Stage 8: Multi-dimensional Confidence & Policy Evaluation
        final confidence = ConfidencePolicyEngine.evaluate(
          extracted: ext,
          topPrediction: topPred,
          source: source,
          modelMeta: activeClassifier.metadata,
          hasValidSourceWallet: srcWalletId != null,
          hasValidDestinationWalletIfTransfer:
              !needsDstWallet || dstWalletId != null,
          hasResolvedUserCategory:
              resolvedCat.categoryId != null || categories.isEmpty,
          isDuplicateCandidate: isDup,
          allFlags: flags,
          mediumConfidenceThresholdOverride: prefs.minAutoSuggestConfidence,
        );

        final requiresConfirm =
            prefs.requireConfirmationBeforeSave ||
            !confidence.canAutoPostUnderPolicy ||
            extractedList.length > 1 ||
            ext.currencyCode != 'VND';

        candidates.add(
          TransactionCandidate(
            draftId: 'aidraft_${_uuid.v4().substring(0, 12)}',
            userId: userId,
            source: source,
            extracted: ext,
            transactionType: ext.transactionType,
            amountMinor: effectiveAmount,
            currencyCode: ext.currencyCode,
            description: ext.description,
            merchant: ext.merchant,
            merchantCanonicalKey: ext.merchantCanonicalKey,
            topPrediction: topPred,
            alternativePredictions: altPreds,
            resolvedCategoryId: resolvedCat.categoryId,
            resolvedCategoryName: resolvedCat.displayCategoryName,
            suggestedCategoryName: resolvedCat.suggestedCategoryName,
            sourceWalletId: srcWalletId,
            destinationWalletId: dstWalletId,
            occurredAt: effectiveDate,
            hasExplicitDate: ext.explicitOccurredAt != null,
            confidence: confidence,
            ambiguityFlags: List.unmodifiable(flags),
            requiresConfirmation: requiresConfirm,
            isDuplicateCandidate: isDup,
            duplicateOfTransactionId: dupTxId,
            transactionFingerprint: fingerprint,
            appliedPersonalizationRuleId: matchedRule?.id,
          ),
        );
      }

      sw.stop();
      final anyRequiresConfirm =
          candidates.isEmpty || candidates.any((c) => c.requiresConfirmation);
      return Success(
        FinancialAnalysisResult(
          request: req,
          candidates: List.unmodifiable(candidates),
          requiresConfirmation: anyRequiresConfirm,
          modelMetadata: prefs.aiClassificationEnabled
              ? _classifier.metadata
              : _ruleFallback.metadata,
          totalElapsedMicros: sw.elapsedMicroseconds,
        ),
      );
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  List<CategoryPrediction> _alignPredictionsWithDirection({
    required List<CategoryPrediction> rawPredictions,
    required String direction,
    String? deterministicSemanticHint,
  }) {
    final targetDir = direction == 'credit' ? 'credit' : 'debit';
    final matching = rawPredictions.where((p) {
      final spec = FinancialTaxonomyCatalog.bySemanticKey(p.semanticKey);
      return spec.direction == targetDir;
    }).toList();

    // Renormalize aligned top candidates cleanly
    if (matching.isNotEmpty) {
      final top = matching.first;
      if (deterministicSemanticHint != null && top.probability < 0.55) {
        final hintSpec = FinancialTaxonomyCatalog.bySemanticKey(
          deterministicSemanticHint,
          fallbackDirection: targetDir,
        );
        return [
          CategoryPrediction(
            semanticKey: hintSpec.semanticKey,
            suggestedDisplayName: hintSpec.suggestedDisplayNameVi,
            probability: 0.76,
            origin: ClassifierInferenceOrigin.deterministicRuleFallback,
          ),
          ...matching,
        ];
      }
      return matching;
    }

    if (deterministicSemanticHint != null) {
      final hintSpec = FinancialTaxonomyCatalog.bySemanticKey(
        deterministicSemanticHint,
        fallbackDirection: targetDir,
      );
      return [
        CategoryPrediction(
          semanticKey: hintSpec.semanticKey,
          suggestedDisplayName: hintSpec.suggestedDisplayNameVi,
          probability: 0.75,
          origin: ClassifierInferenceOrigin.deterministicRuleFallback,
        ),
      ];
    }

    final fallbackKey = targetDir == 'credit' ? 'income.other' : 'other';
    final fallbackSpec = FinancialTaxonomyCatalog.bySemanticKey(fallbackKey);
    return [
      CategoryPrediction(
        semanticKey: fallbackKey,
        suggestedDisplayName: fallbackSpec.suggestedDisplayNameVi,
        probability: 0.30,
        origin: ClassifierInferenceOrigin.deterministicRuleFallback,
      ),
    ];
  }

  @override
  Future<Result<TransactionEntity>> confirmCandidateDraft({
    required String userId,
    required TransactionCandidate candidate,
    String? operationId,
  }) async {
    final ledgerKind = candidate.transactionType.toLedgerKind;
    if (ledgerKind == null) {
      return const Err(
        ValidationFailure(
          message: 'Loại giao dịch không thể ghi sổ trực tiếp.',
        ),
      );
    }

    final opId = operationId ?? 'ai_${candidate.draftId}';
    final notePrefix = switch (candidate.transactionType) {
      FinancialTransactionType.refund => 'Hoàn tiền (Refund) · ',
      FinancialTransactionType.loanDisbursement => 'Giải ngân vay · ',
      FinancialTransactionType.loanRepayment => 'Trả nợ vay · ',
      FinancialTransactionType.externalTransfer =>
        candidate.extracted.recipient != null
            ? 'Chuyển cho ${candidate.extracted.recipient} · '
            : '',
      _ => '',
    };

    final txRes = await _transactionRepository.createTransaction(
      operationId: opId,
      userId: userId,
      walletId: candidate.sourceWalletId!,
      targetWalletId: ledgerKind == TransactionKind.transfer
          ? candidate.destinationWalletId
          : null,
      categoryId: candidate.resolvedCategoryId,
      categoryName: candidate.resolvedCategoryName,
      kind: ledgerKind,
      amountMinor: candidate.amountMinor,
      merchant: candidate.description,
      note: '${notePrefix}Phân loại Offline AI (${candidate.topPrediction.semanticKey})',
      occurredAt: candidate.occurredAt,
    );

    if (txRes is Success<TransactionEntity>) {
      try {
        await _localSync.deletePendingDraft(
          userId: userId,
          draftId: candidate.draftId,
        );
      } catch (_) {}
    }
    return txRes;
  }

  @override
  Future<Result<PersonalizationRule>> saveCategoryCorrection({
    required String userId,
    required String merchantDisplay,
    required String merchantCanonicalKey,
    required String selectedCategoryId,
    required String selectedCategoryName,
    required String semanticKey,
    String directionCondition = 'any',
    String sourceContext = 'any',
  }) async {
    try {
      final rule = await _localSync.upsertCorrectionRule(
        userId: userId,
        merchantDisplay: merchantDisplay,
        merchantCanonicalKey: merchantCanonicalKey,
        selectedCategoryId: selectedCategoryId,
        selectedCategoryName: selectedCategoryName,
        semanticKey: semanticKey,
        directionCondition: directionCondition,
        sourceContext: sourceContext,
        modelVersion: _classifier.metadata.modelVersion,
      );
      return Success(rule);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Stream<Result<List<TransactionCandidate>>> watchPendingDrafts(String userId) {
    return _localSync
        .watchPendingDrafts(userId)
        .map<Result<List<TransactionCandidate>>>((list) => Success(list))
        .transform(
          StreamTransformer<
            Result<List<TransactionCandidate>>,
            Result<List<TransactionCandidate>>
          >.fromHandlers(
            handleError: (e, _, sink) => sink.add(Err(ErrorMapper.map(e))),
          ),
        );
  }

  @override
  Future<Result<void>> savePendingDraft(TransactionCandidate draft) async {
    try {
      await _localSync.savePendingDraft(draft);
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> deletePendingDraft({
    required String userId,
    required String draftId,
  }) async {
    try {
      await _localSync.deletePendingDraft(userId: userId, draftId: draftId);
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Stream<Result<List<PersonalizationRule>>> watchPersonalizationRules(
    String userId,
  ) {
    return _localSync
        .watchRules(userId)
        .map<Result<List<PersonalizationRule>>>((list) => Success(list))
        .transform(
          StreamTransformer<
            Result<List<PersonalizationRule>>,
            Result<List<PersonalizationRule>>
          >.fromHandlers(
            handleError: (e, _, sink) => sink.add(Err(ErrorMapper.map(e))),
          ),
        );
  }

  @override
  Future<Result<void>> deletePersonalizationRule({
    required String userId,
    required String ruleId,
  }) async {
    try {
      await _localSync.deleteRule(userId: userId, ruleId: ruleId);
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> clearAllPersonalizationData(String userId) async {
    try {
      await _localSync.clearAllPersonalization(userId);
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Stream<Result<UserAiClassificationPreferences>> watchPreferences(
    String userId,
  ) {
    return _localSync
        .watchPreferences(userId)
        .map<Result<UserAiClassificationPreferences>>((p) => Success(p))
        .transform(
          StreamTransformer<
            Result<UserAiClassificationPreferences>,
            Result<UserAiClassificationPreferences>
          >.fromHandlers(
            handleError: (e, _, sink) => sink.add(Err(ErrorMapper.map(e))),
          ),
        );
  }

  @override
  Future<Result<void>> updatePreferences(
    UserAiClassificationPreferences preferences,
  ) async {
    try {
      await _localSync.savePreferences(preferences);
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
