import '../entities/financial_ai_entities.dart';

/// Pure Domain interface for offline financial text classification (Phase 9).
/// Zero Flutter/Firebase imports.
abstract interface class FinancialClassifier {
  Future<ClassificationResult> classify(String normalizedText);

  Future<void> initialize();

  Future<void> dispose();

  FinancialModelMetadata get metadata;
}
