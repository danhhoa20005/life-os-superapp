import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/user_entity.dart';

class UserModel {
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
  final int schemaVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserModel({
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
    this.schemaVersion = 2,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdTs = data['createdAt'];
    final updatedTs = data['updatedAt'];
    final rawProviders = data['authProviders'];
    final parsedProviders = rawProviders is Iterable
        ? rawProviders
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>['password'];

    return UserModel(
      id: (data['id'] as String?) ?? doc.id,
      email: (data['email'] as String?) ?? '',
      fullName: (data['fullName'] as String?) ?? 'Người dùng Life OS',
      photoUrl: data['photoUrl'] as String?,
      phoneNumber: data['phoneNumber'] as String?,
      emailVerified: (data['emailVerified'] as bool?) ?? false,
      authProviders: parsedProviders.isEmpty
          ? const <String>['password']
          : parsedProviders,
      timezone: (data['timezone'] as String?) ?? 'Asia/Ho_Chi_Minh',
      onboardingCompleted: (data['onboardingCompleted'] as bool?) ?? false,
      availabilityOptIn: (data['availabilityOptIn'] as bool?) ?? false,
      activeFamilyId: data['activeFamilyId'] as String?,
      schemaVersion: (data['schemaVersion'] as int?) ?? 2,
      createdAt: createdTs is Timestamp ? createdTs.toDate() : DateTime.now(),
      updatedAt: updatedTs is Timestamp ? updatedTs.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'email': email,
      'fullName': fullName,
      'photoUrl': photoUrl,
      'phoneNumber': phoneNumber,
      'emailVerified': emailVerified,
      'authProviders': authProviders,
      'timezone': timezone,
      'onboardingCompleted': onboardingCompleted,
      'availabilityOptIn': availabilityOptIn,
      'activeFamilyId': activeFamilyId,
      'schemaVersion': schemaVersion,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  UserEntity toEntity() {
    return UserEntity(
      id: id,
      email: email,
      fullName: fullName,
      photoUrl: photoUrl,
      phoneNumber: phoneNumber,
      emailVerified: emailVerified,
      authProviders: authProviders,
      timezone: timezone,
      onboardingCompleted: onboardingCompleted,
      availabilityOptIn: availabilityOptIn,
      activeFamilyId: activeFamilyId,
      createdAt: createdAt,
    );
  }
}
