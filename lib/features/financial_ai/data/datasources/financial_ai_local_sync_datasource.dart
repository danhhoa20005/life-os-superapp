import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/financial_ai_entities.dart';
import '../inference/taxonomy_catalog.dart';
import '../normalization/financial_text_normalizer.dart';

/// Phase 10 & Phase 15 — User-Isolated Personalization, Pending Drafts & AI Preferences DataSource.
/// Uses existing Cloud Firestore offline persistence + instant in-memory per-user cache
/// so offline inference in Airplane Mode requires ZERO network round-trips!
/// Strictly isolated under `/users/{userId}/**` (never shared across family members).
class FinancialAiLocalSyncDataSource {
  final FirebaseFirestore _firestore;
  static const Uuid _uuid = Uuid();

  final Map<String, List<PersonalizationRule>> _rulesMemoryCache = {};
  final Map<String, UserAiClassificationPreferences> _prefsMemoryCache = {};

  FinancialAiLocalSyncDataSource(this._firestore);

  CollectionReference<Map<String, dynamic>> _rulesCol(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('ai_personalization_rules');

  CollectionReference<Map<String, dynamic>> _correctionsCol(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('ai_category_corrections');

  CollectionReference<Map<String, dynamic>> _draftsCol(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('ai_pending_drafts');

  DocumentReference<Map<String, dynamic>> _prefsRef(String userId) => _firestore
      .collection('users')
      .doc(userId)
      .collection('ai_preferences')
      .doc('settings');

  CollectionReference<Map<String, dynamic>> _legacyMerchantRulesCol(
    String userId,
  ) => _firestore.collection('users').doc(userId).collection('merchant_rules');

  PersonalizationRule _mapRule(
    String id,
    String userId,
    Map<String, dynamic> d,
  ) {
    final ts = d['lastCorrectedAt'];
    final rawKind = (d['ruleKind'] as String?) ?? 'category';
    final kind = rawKind == 'participantNickname' || rawKind == 'nickname'
        ? 'nickname'
        : rawKind == 'wallet'
        ? 'wallet'
        : 'category';
    return PersonalizationRule(
      id: id,
      userId: userId,
      ruleKind: kind,
      merchantCanonicalKey: (d['merchantCanonicalKey'] as String?) ?? '',
      merchantDisplay: (d['merchantDisplay'] as String?) ?? '',
      selectedCategoryId: (d['selectedCategoryId'] as String?) ?? '',
      selectedCategoryName: (d['selectedCategoryName'] as String?) ?? '',
      semanticKey: (d['semanticKey'] as String?) ?? 'other',
      directionCondition: (d['directionCondition'] as String?) ?? 'any',
      sourceContext: (d['sourceContext'] as String?) ?? 'any',
      minAmountMinor: (d['minAmountMinor'] as num?)?.toInt(),
      maxAmountMinor: (d['maxAmountMinor'] as num?)?.toInt(),
      preferredWalletId: d['preferredWalletId'] as String?,
      preferredWalletName: d['preferredWalletName'] as String?,
      participantUserId: d['participantUserId'] as String?,
      participantDisplayName: d['participantDisplayName'] as String?,
      confirmationCount: (d['confirmationCount'] as num?)?.toInt() ?? 1,
      lastCorrectedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      priority: (d['priority'] as num?)?.toInt() ?? 10,
      ruleConfidence: (d['ruleConfidence'] as num?)?.toDouble() ?? 0.90,
      modelVersion: (d['modelVersion'] as String?) ?? '1.0.0',
      isEnabled: (d['isEnabled'] as bool?) ?? true,
    );
  }

  Future<List<PersonalizationRule>> getRulesForUser(String userId) async {
    final cached = _rulesMemoryCache[userId];
    if (cached != null) return cached;
    try {
      final snap = await _rulesCol(userId).get();
      final list = snap.docs
          .map((doc) => _mapRule(doc.id, userId, doc.data()))
          .toList();

      // Legacy fallback: include any rules saved only in `merchant_rules`
      try {
        final legacySnap = await _legacyMerchantRulesCol(userId).get();
        final knownKeys = list.map((r) => r.merchantCanonicalKey).toSet();
        for (final ldoc in legacySnap.docs) {
          final ld = ldoc.data();
          final canon = (ld['merchantKey'] as String?) ?? ldoc.id;
          if (canon.isEmpty || knownKeys.contains(canon)) continue;
          final ts = ld['updatedAt'];
          list.add(
            PersonalizationRule(
              id: 'legacy_${ldoc.id}',
              userId: userId,
              merchantCanonicalKey: canon,
              merchantDisplay:
                  (ld['merchantSample'] as String?) ??
                  canon.replaceAll('_', ' '),
              selectedCategoryId: '',
              selectedCategoryName: (ld['categoryName'] as String?) ?? '',
              semanticKey: 'other',
              directionCondition: (ld['direction'] as String?) ?? 'debit',
              sourceContext: 'bank_notification',
              confirmationCount: (ld['hits'] as num?)?.toInt() ?? 1,
              lastCorrectedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
              priority: 8,
              ruleConfidence: 0.88,
              modelVersion: 'legacy_merchant_rules',
              isEnabled: true,
            ),
          );
        }
      } catch (_) {}

      list.sort((a, b) {
        final p = b.priority.compareTo(a.priority);
        return p != 0 ? p : b.confirmationCount.compareTo(a.confirmationCount);
      });
      _rulesMemoryCache[userId] = list;
      return list;
    } catch (_) {
      return const [];
    }
  }

  Stream<List<PersonalizationRule>> watchRules(String userId) {
    return _rulesCol(userId).snapshots().map((snap) {
      final list =
          snap.docs.map((doc) => _mapRule(doc.id, userId, doc.data())).toList()
            ..sort((a, b) {
              final p = b.priority.compareTo(a.priority);
              return p != 0
                  ? p
                  : b.lastCorrectedAt.compareTo(a.lastCorrectedAt);
            });
      _rulesMemoryCache[userId] = list;
      return list;
    });
  }

  Future<PersonalizationRule> upsertCorrectionRule({
    required String userId,
    required String merchantDisplay,
    required String merchantCanonicalKey,
    required String selectedCategoryId,
    required String selectedCategoryName,
    required String semanticKey,
    required String directionCondition,
    required String sourceContext,
    required String modelVersion,
    String ruleKind = 'category',
    String? preferredWalletId,
    String? preferredWalletName,
    String? participantUserId,
    String? participantDisplayName,
    String? ruleIdOverride,
  }) async {
    final now = DateTime.now();
    final cleanKey =
        FinancialTextNormalizer.canonicalizeMerchant(merchantCanonicalKey) ??
        merchantCanonicalKey.trim().toLowerCase().replaceAll(
          RegExp(r'\s+'),
          '_',
        );
    // Deterministic composite rule ID per (ruleKind + merchantKey + direction + sourceContext)
    // so conditional rules and participant nickname rules coexist cleanly!
    final ruleHash = sha256
        .convert(
          utf8.encode('$ruleKind|$cleanKey|$directionCondition|$sourceContext'),
        )
        .toString()
        .substring(0, 20);
    final ruleId = (ruleIdOverride != null && ruleIdOverride.trim().isNotEmpty)
        ? ruleIdOverride.trim()
        : 'prule_$ruleHash';
    final docRef = _rulesCol(userId).doc(ruleId);

    var confirmations = 1;
    try {
      final existing = await docRef.get();
      if (existing.exists) {
        final prevCat = existing.data()?['selectedCategoryId'] as String?;
        final prevCnt =
            (existing.data()?['confirmationCount'] as num?)?.toInt() ?? 1;
        confirmations = (prevCat == selectedCategoryId) ? (prevCnt + 1) : 1;
      }
    } catch (_) {}

    final confidence = (0.86 + (confirmations * 0.03)).clamp(0.86, 0.98);
    final rule = PersonalizationRule(
      id: ruleId,
      userId: userId,
      ruleKind: ruleKind,
      merchantCanonicalKey: cleanKey,
      merchantDisplay: merchantDisplay,
      selectedCategoryId: selectedCategoryId,
      selectedCategoryName: selectedCategoryName,
      semanticKey: semanticKey,
      directionCondition: directionCondition,
      sourceContext: sourceContext,
      preferredWalletId: preferredWalletId,
      preferredWalletName: preferredWalletName,
      participantUserId: participantUserId,
      participantDisplayName: participantDisplayName,
      confirmationCount: confirmations,
      lastCorrectedAt: now,
      priority: 10 + confirmations.clamp(0, 10),
      ruleConfidence: confidence,
      modelVersion: modelVersion,
      isEnabled: true,
    );

    // Update memory cache immediately for zero-latency offline reuse!
    final existingMem = List<PersonalizationRule>.from(
      _rulesMemoryCache[userId] ?? const [],
    )..removeWhere((r) => r.id == ruleId);
    existingMem.insert(0, rule);
    _rulesMemoryCache[userId] = existingMem;

    final batch = _firestore.batch();
    batch.set(docRef, {
      'id': ruleId,
      'ownerId': userId,
      'ruleKind': ruleKind,
      'merchantCanonicalKey': cleanKey,
      'merchantDisplay': merchantDisplay,
      'selectedCategoryId': selectedCategoryId,
      'selectedCategoryName': selectedCategoryName,
      'semanticKey': semanticKey,
      'directionCondition': directionCondition,
      'sourceContext': sourceContext,
      if (preferredWalletId != null) 'preferredWalletId': preferredWalletId,
      if (preferredWalletName != null)
        'preferredWalletName': preferredWalletName,
      if (participantUserId != null) 'participantUserId': participantUserId,
      if (participantDisplayName != null)
        'participantDisplayName': participantDisplayName,
      'confirmationCount': confirmations,
      'lastCorrectedAt': Timestamp.fromDate(now),
      'priority': rule.priority,
      'ruleConfidence': confidence,
      'modelVersion': modelVersion,
      'isEnabled': true,
    }, SetOptions(merge: true));

    final corrId = 'corr_${_uuid.v4()}';
    batch.set(_correctionsCol(userId).doc(corrId), {
      'id': corrId,
      'ownerId': userId,
      'merchantCanonicalKey': cleanKey,
      'selectedCategoryId': selectedCategoryId,
      'selectedCategoryName': selectedCategoryName,
      'semanticKey': semanticKey,
      'directionCondition': directionCondition,
      'sourceContext': sourceContext,
      'modelVersion': modelVersion,
      'createdAt': Timestamp.fromDate(now),
    });

    await batch.commit();
    return rule;
  }

  Future<void> deleteRule({
    required String userId,
    required String ruleId,
  }) async {
    _rulesMemoryCache[userId] = List<PersonalizationRule>.from(
      _rulesMemoryCache[userId] ?? const [],
    )..removeWhere((r) => r.id == ruleId);
    await _rulesCol(userId).doc(ruleId).delete();
  }

  Future<void> clearAllPersonalization(String userId) async {
    _rulesMemoryCache.remove(userId);
    final rulesSnap = await _rulesCol(userId).get();
    final corrSnap = await _correctionsCol(userId).get();
    final batch = _firestore.batch();
    for (final d in rulesSnap.docs) {
      batch.delete(d.reference);
    }
    for (final d in corrSnap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  Future<UserAiClassificationPreferences> getPreferences(String userId) async {
    final cached = _prefsMemoryCache[userId];
    if (cached != null) return cached;
    try {
      final snap = await _prefsRef(userId).get();
      final prefs = _mapPrefs(userId, snap.data());
      _prefsMemoryCache[userId] = prefs;
      return prefs;
    } catch (_) {
      return UserAiClassificationPreferences(userId: userId);
    }
  }

  UserAiClassificationPreferences _mapPrefs(
    String userId,
    Map<String, dynamic>? d,
  ) {
    if (d == null) return UserAiClassificationPreferences(userId: userId);
    final rawThreshold =
        (d['minAutoSuggestConfidence'] as num?)?.toDouble() ?? 0.52;
    return UserAiClassificationPreferences(
      userId: userId,
      aiClassificationEnabled: (d['aiClassificationEnabled'] as bool?) ?? true,
      personalizationEnabled: (d['personalizationEnabled'] as bool?) ?? true,
      autoClassifyBankNotifications:
          (d['autoClassifyBankNotifications'] as bool?) ?? true,
      requireConfirmationBeforeSave:
          (d['requireConfirmationBeforeSave'] as bool?) ?? true,
      minAutoSuggestConfidence: rawThreshold.clamp(0.35, 0.85),
    );
  }

  Stream<UserAiClassificationPreferences> watchPreferences(String userId) {
    return _prefsRef(userId).snapshots().map((snap) {
      final prefs = _mapPrefs(userId, snap.data());
      _prefsMemoryCache[userId] = prefs;
      return prefs;
    });
  }

  Future<void> savePreferences(UserAiClassificationPreferences prefs) async {
    _prefsMemoryCache[prefs.userId] = prefs;
    await _prefsRef(prefs.userId).set({
      'ownerId': prefs.userId,
      'aiClassificationEnabled': prefs.aiClassificationEnabled,
      'personalizationEnabled': prefs.personalizationEnabled,
      'autoClassifyBankNotifications': prefs.autoClassifyBankNotifications,
      'requireConfirmationBeforeSave': prefs.requireConfirmationBeforeSave,
      'minAutoSuggestConfidence': prefs.minAutoSuggestConfidence.clamp(
        0.35,
        0.85,
      ),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  Future<void> savePendingDraft(TransactionCandidate draft) async {
    await _draftsCol(draft.userId).doc(draft.draftId).set({
      'id': draft.draftId,
      'ownerId': draft.userId,
      'source': draft.source.name,
      'transactionType': draft.transactionType.name,
      'amountMinor': draft.amountMinor,
      'currencyCode': draft.currencyCode,
      'description': draft.description,
      'merchant': draft.merchant,
      'merchantCanonicalKey': draft.merchantCanonicalKey,
      'semanticKey': draft.topPrediction.semanticKey,
      'probability': draft.topPrediction.probability,
      'resolvedCategoryId': draft.resolvedCategoryId,
      'resolvedCategoryName': draft.resolvedCategoryName,
      'suggestedCategoryName': draft.suggestedCategoryName,
      'sourceWalletId': draft.sourceWalletId,
      'destinationWalletId': draft.destinationWalletId,
      'occurredAt': Timestamp.fromDate(draft.occurredAt),
      'hasExplicitDate': draft.hasExplicitDate,
      'confidenceTier': draft.confidence.tier.name,
      'transactionFingerprint': draft.transactionFingerprint,
      'createdAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  Future<void> deletePendingDraft({
    required String userId,
    required String draftId,
  }) async {
    await _draftsCol(userId).doc(draftId).delete();
  }

  Stream<List<TransactionCandidate>> watchPendingDrafts(String userId) {
    return _draftsCol(
      userId,
    ).orderBy('createdAt', descending: true).limit(30).snapshots().map((snap) {
      return snap.docs.map((doc) {
        final d = doc.data();
        final typeName = (d['transactionType'] as String?) ?? 'expense';
        final txType =
            FinancialTransactionType.values
                .where((t) => t.name == typeName)
                .firstOrNull ??
            FinancialTransactionType.expense;
        final srcName = (d['source'] as String?) ?? 'manualText';
        final src =
            FinancialInputSource.values
                .where((s) => s.name == srcName)
                .firstOrNull ??
            FinancialInputSource.manualText;
        final semKey = (d['semanticKey'] as String?) ?? 'other';
        final prob = (d['probability'] as num?)?.toDouble() ?? 0.5;
        final spec = FinancialTaxonomyCatalog.bySemanticKey(semKey);
        final ts = d['occurredAt'];
        final occurredAt = ts is Timestamp ? ts.toDate() : DateTime.now();
        final amt = (d['amountMinor'] as num?)?.toInt() ?? 0;
        final desc = (d['description'] as String?) ?? 'Giao dịch chờ duyệt';

        final pred = CategoryPrediction(
          semanticKey: semKey,
          suggestedDisplayName: spec.suggestedDisplayNameVi,
          probability: prob,
          origin: ClassifierInferenceOrigin.fastTextIsolateInt8,
        );
        final extracted = ExtractedFinancialEntity(
          rawSegment: desc,
          normalizedSegment: desc,
          classifierInput: desc.toLowerCase(),
          amountMinor: amt,
          transactionType: txType,
          description: desc,
          merchant: d['merchant'] as String?,
          merchantCanonicalKey: d['merchantCanonicalKey'] as String?,
          amountConfidence: 0.95,
          typeConfidence: 0.90,
          merchantConfidence: 0.80,
        );
        final tierName = (d['confidenceTier'] as String?) ?? 'mediumConfidence';
        final tier =
            ConfidenceTier.values
                .where((t) => t.name == tierName)
                .firstOrNull ??
            ConfidenceTier.mediumConfidence;

        return TransactionCandidate(
          draftId: doc.id,
          userId: userId,
          source: src,
          extracted: extracted,
          transactionType: txType,
          amountMinor: amt,
          currencyCode: (d['currencyCode'] as String?) ?? 'VND',
          description: desc,
          merchant: d['merchant'] as String?,
          merchantCanonicalKey: d['merchantCanonicalKey'] as String?,
          topPrediction: pred,
          resolvedCategoryId: d['resolvedCategoryId'] as String?,
          resolvedCategoryName:
              (d['resolvedCategoryName'] as String?) ??
              spec.defaultSystemCategoryName,
          suggestedCategoryName:
              (d['suggestedCategoryName'] as String?) ??
              spec.suggestedDisplayNameVi,
          sourceWalletId: d['sourceWalletId'] as String?,
          destinationWalletId: d['destinationWalletId'] as String?,
          occurredAt: occurredAt,
          hasExplicitDate: (d['hasExplicitDate'] as bool?) ?? false,
          confidence: ClassificationConfidence(
            amountConfidence: 0.95,
            typeConfidence: 0.90,
            categoryConfidence: prob,
            merchantConfidence: 0.80,
            sourceConfidence: 0.88,
            tier: tier,
            canAutoPostUnderPolicy: false,
          ),
          requiresConfirmation: true,
          transactionFingerprint:
              (d['transactionFingerprint'] as String?) ?? '',
        );
      }).toList();
    });
  }
}
