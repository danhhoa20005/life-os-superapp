import 'package:equatable/equatable.dart';

class SourceConsentEntity extends Equatable {
  final String sourceId;
  final String ownerId;
  final bool enabled;
  final bool autoConfirmSignals;
  final List<String> allowedPackages;
  final DateTime updatedAt;

  const SourceConsentEntity({
    required this.sourceId,
    required this.ownerId,
    required this.enabled,
    this.autoConfirmSignals = false,
    required this.allowedPackages,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
        sourceId,
        ownerId,
        enabled,
        autoConfirmSignals,
        allowedPackages,
        updatedAt,
      ];
}

enum IngestionOutcomeKind {
  createdProvisional,
  upgradedToVerified,
  duplicateIgnored,
  blockedOtpOrSecret,
  blockedConsentDisabled,
  ignoredPackageOrFormat,
}

class IngestionOutcome extends Equatable {
  final IngestionOutcomeKind kind;
  final String? transactionId;
  final String message;

  const IngestionOutcome({
    required this.kind,
    this.transactionId,
    required this.message,
  });

  @override
  List<Object?> get props => [kind, transactionId, message];
}
