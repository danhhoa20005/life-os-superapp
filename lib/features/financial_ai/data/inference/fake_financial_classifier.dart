import '../../domain/entities/financial_ai_entities.dart';
import '../../domain/services/financial_classifier.dart';
import 'taxonomy_catalog.dart';

/// Deterministic in-memory test double for [FinancialClassifier] (Phase 9).
/// Supports simulating model load failure, latency, or exact canned predictions.
class FakeFinancialClassifier implements FinancialClassifier {
  final Map<String, (String semanticKey, double probability)> cannedResponses;
  final bool shouldThrowOnInitialize;
  final bool shouldThrowOnClassify;
  bool _isInitialized = false;
  int initializeCallCount = 0;
  int classifyCallCount = 0;

  FakeFinancialClassifier({
    this.cannedResponses = const {},
    this.shouldThrowOnInitialize = false,
    this.shouldThrowOnClassify = false,
  });

  @override
  FinancialModelMetadata get metadata => FinancialModelMetadata(
    modelId: 'fake_classifier_test',
    modelVersion: '1.0.0-test',
    architecture: 'FakeFinancialClassifier',
    sizeBytes: 1024,
    sha256: 'fake_sha256',
    numClasses: FinancialTaxonomyCatalog.specs.length,
    isLoaded: _isInitialized,
  );

  @override
  Future<void> initialize() async {
    initializeCallCount++;
    if (shouldThrowOnInitialize) {
      throw StateError('Simulated model initialization failure');
    }
    _isInitialized = true;
  }

  @override
  Future<ClassificationResult> classify(String normalizedText) async {
    classifyCallCount++;
    if (shouldThrowOnClassify) {
      throw StateError('Simulated inference failure');
    }
    for (final entry in cannedResponses.entries) {
      if (normalizedText.toLowerCase().contains(entry.key.toLowerCase())) {
        final spec = FinancialTaxonomyCatalog.bySemanticKey(entry.value.$1);
        return ClassificationResult(
          predictions: [
            CategoryPrediction(
              semanticKey: entry.value.$1,
              suggestedDisplayName: spec.suggestedDisplayNameVi,
              probability: entry.value.$2,
              origin: ClassifierInferenceOrigin.fakeTestClassifier,
            ),
          ],
          latencyMicros: 42,
          modelVersion: metadata.modelVersion,
          origin: ClassifierInferenceOrigin.fakeTestClassifier,
        );
      }
    }
    return const ClassificationResult(
      predictions: [
        CategoryPrediction(
          semanticKey: 'other',
          suggestedDisplayName: 'Chi tiêu khác',
          probability: 0.30,
          origin: ClassifierInferenceOrigin.fakeTestClassifier,
        ),
      ],
      latencyMicros: 42,
      modelVersion: '1.0.0-test',
      origin: ClassifierInferenceOrigin.fakeTestClassifier,
    );
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
  }
}
