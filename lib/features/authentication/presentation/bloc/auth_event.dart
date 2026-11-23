import 'package:equatable/equatable.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

final class AuthSubscriptionRequested extends AuthEvent {
  const AuthSubscriptionRequested();
}

final class AuthSignInSubmitted extends AuthEvent {
  final String email;
  final String password;

  const AuthSignInSubmitted({required this.email, required this.password});

  @override
  List<Object?> get props => [email, password];
}

final class AuthSignUpSubmitted extends AuthEvent {
  final String email;
  final String password;
  final String? confirmPassword;
  final String fullName;
  final String? phoneNumber;
  final bool acceptedTerms;

  const AuthSignUpSubmitted({
    required this.email,
    required this.password,
    this.confirmPassword,
    required this.fullName,
    this.phoneNumber,
    this.acceptedTerms = true,
  });

  @override
  List<Object?> get props => [
    email,
    password,
    confirmPassword,
    fullName,
    phoneNumber,
    acceptedTerms,
  ];
}

final class AuthGoogleSignInRequested extends AuthEvent {
  const AuthGoogleSignInRequested();
}

final class AuthGoogleLinkRequested extends AuthEvent {
  const AuthGoogleLinkRequested();
}

final class AuthPasswordResetRequested extends AuthEvent {
  final String email;
  const AuthPasswordResetRequested(this.email);

  @override
  List<Object?> get props => [email];
}

final class AuthEmailVerificationRequested extends AuthEvent {
  const AuthEmailVerificationRequested();
}

final class AuthUserReloadRequested extends AuthEvent {
  const AuthUserReloadRequested();
}

final class AuthProfileUpdateSubmitted extends AuthEvent {
  final String fullName;
  final String? phoneNumber;
  final String? timezone;

  const AuthProfileUpdateSubmitted({
    required this.fullName,
    this.phoneNumber,
    this.timezone,
  });

  @override
  List<Object?> get props => [fullName, phoneNumber, timezone];
}

final class AuthPasswordChangeSubmitted extends AuthEvent {
  final String? currentPassword;
  final String newPassword;
  final String confirmPassword;

  const AuthPasswordChangeSubmitted({
    this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
  });

  @override
  List<Object?> get props => [currentPassword, newPassword, confirmPassword];
}

final class AuthOnboardingCompleted extends AuthEvent {
  const AuthOnboardingCompleted();
}

final class AuthAvailabilitySharingToggled extends AuthEvent {
  final bool enabled;
  const AuthAvailabilitySharingToggled(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

final class AuthActiveFamilyChanged extends AuthEvent {
  final String familyId;
  const AuthActiveFamilyChanged(this.familyId);

  @override
  List<Object?> get props => [familyId];
}

final class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}
