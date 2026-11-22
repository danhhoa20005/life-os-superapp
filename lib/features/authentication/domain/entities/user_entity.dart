import 'package:equatable/equatable.dart';

class UserEntity extends Equatable {
  final String id;
  final String email;
  final String fullName;
  final String? photoUrl;
  final String? phoneNumber;
  final bool emailVerified;
  final List<String> authProviders;
  final String timezone;
  final bool onboardingCompleted;
  final bool availabilityOptIn;
  final String? activeFamilyId;
  final DateTime createdAt;

  const UserEntity({
    required this.id,
    required this.email,
    required this.fullName,
    this.photoUrl,
    this.phoneNumber,
    this.emailVerified = false,
    this.authProviders = const <String>['password'],
    required this.timezone,
    required this.onboardingCompleted,
    required this.availabilityOptIn,
    this.activeFamilyId,
    required this.createdAt,
  });

  bool get isGoogleLinked => authProviders.contains('google.com');

  bool get hasPasswordProvider => authProviders.contains('password');

  String get initials {
    final trimmed = fullName.trim();
    if (trimmed.isNotEmpty) {
      final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      }
      return parts.first[0].toUpperCase();
    }
    if (email.isNotEmpty) {
      return email[0].toUpperCase();
    }
    return 'L';
  }

  UserEntity copyWith({
    String? fullName,
    String? photoUrl,
    bool clearPhotoUrl = false,
    String? phoneNumber,
    bool clearPhoneNumber = false,
    bool? emailVerified,
    List<String>? authProviders,
    String? timezone,
    bool? onboardingCompleted,
    bool? availabilityOptIn,
    String? activeFamilyId,
    bool clearActiveFamily = false,
  }) {
    return UserEntity(
      id: id,
      email: email,
      fullName: fullName ?? this.fullName,
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      phoneNumber: clearPhoneNumber ? null : (phoneNumber ?? this.phoneNumber),
      emailVerified: emailVerified ?? this.emailVerified,
      authProviders: authProviders ?? this.authProviders,
      timezone: timezone ?? this.timezone,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      availabilityOptIn: availabilityOptIn ?? this.availabilityOptIn,
      activeFamilyId: clearActiveFamily ? null : (activeFamilyId ?? this.activeFamilyId),
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        email,
        fullName,
        photoUrl,
        phoneNumber,
        emailVerified,
        authProviders,
        timezone,
        onboardingCompleted,
        availabilityOptIn,
        activeFamilyId,
        createdAt,
      ];
}
