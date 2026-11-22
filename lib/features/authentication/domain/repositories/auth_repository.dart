import '../../../../core/error/app_exception.dart';
import '../entities/user_entity.dart';

abstract interface class AuthRepository {
  Stream<UserEntity?> watchCurrentUser();

  UserEntity? get currentCachedUser;

  Future<Result<UserEntity>> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
  });

  Future<Result<UserEntity>> signIn({
    required String email,
    required String password,
  });

  Future<Result<UserEntity>> signInWithGoogle();

  Future<Result<UserEntity>> linkGoogleAccount();

  Future<Result<void>> sendPasswordReset({required String email});

  Future<Result<void>> sendEmailVerification();

  Future<Result<UserEntity>> reloadCurrentUser();

  Future<Result<UserEntity>> updateUserProfile({
    required String userId,
    required String fullName,
    String? phoneNumber,
    String? timezone,
  });

  Future<Result<UserEntity>> changePassword({
    required String userId,
    String? currentPassword,
    required String newPassword,
  });

  Future<Result<UserEntity>> completeOnboarding({required String userId});

  Future<Result<UserEntity>> updatePrivacySettings({
    required String userId,
    bool? availabilityOptIn,
    String? activeFamilyId,
  });

  Future<Result<void>> signOut();
}
