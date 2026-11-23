import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/firebase_auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  final FirebaseAuthRemoteDataSource _remoteDataSource;
  UserEntity? _cachedUser;

  AuthRepositoryImpl(this._remoteDataSource);

  @override
  UserEntity? get currentCachedUser => _cachedUser;

  @override
  Stream<UserEntity?> watchCurrentUser() {
    return _remoteDataSource.watchUser().map((model) {
      _cachedUser = model?.toEntity();
      return _cachedUser;
    });
  }

  @override
  Future<Result<UserEntity>> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
  }) async {
    try {
      final model = await _remoteDataSource.signUp(
        email: email,
        password: password,
        fullName: fullName,
        phoneNumber: phoneNumber,
      );
      final entity = model.toEntity();
      _cachedUser = entity;
      return Success(entity);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<UserEntity>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final model = await _remoteDataSource.signIn(
        email: email,
        password: password,
      );
      final entity = model.toEntity();
      _cachedUser = entity;
      return Success(entity);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<UserEntity>> signInWithGoogle() async {
    try {
      final model = await _remoteDataSource.signInWithGoogle();
      final entity = model.toEntity();
      _cachedUser = entity;
      return Success(entity);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<UserEntity>> linkGoogleAccount() async {
    try {
      final model = await _remoteDataSource.linkGoogleAccount();
      final entity = model.toEntity();
      _cachedUser = entity;
      return Success(entity);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> sendPasswordReset({required String email}) async {
    try {
      await _remoteDataSource.sendPasswordReset(email: email);
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> sendEmailVerification() async {
    try {
      await _remoteDataSource.sendEmailVerification();
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<UserEntity>> reloadCurrentUser() async {
    try {
      final model = await _remoteDataSource.reloadCurrentUser();
      final entity = model.toEntity();
      _cachedUser = entity;
      return Success(entity);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<UserEntity>> updateUserProfile({
    required String userId,
    required String fullName,
    String? phoneNumber,
    String? timezone,
  }) async {
    try {
      final model = await _remoteDataSource.updateUserProfile(
        userId: userId,
        fullName: fullName,
        phoneNumber: phoneNumber,
        timezone: timezone,
      );
      final entity = model.toEntity();
      _cachedUser = entity;
      return Success(entity);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<UserEntity>> changePassword({
    required String userId,
    String? currentPassword,
    required String newPassword,
  }) async {
    try {
      final model = await _remoteDataSource.changePassword(
        userId: userId,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      final entity = model.toEntity();
      _cachedUser = entity;
      return Success(entity);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<UserEntity>> completeOnboarding({
    required String userId,
  }) async {
    try {
      final model = await _remoteDataSource.completeOnboarding(userId: userId);
      final entity = model.toEntity();
      _cachedUser = entity;
      return Success(entity);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<UserEntity>> updatePrivacySettings({
    required String userId,
    bool? availabilityOptIn,
    String? activeFamilyId,
  }) async {
    try {
      final model = await _remoteDataSource.updatePrivacySettings(
        userId: userId,
        availabilityOptIn: availabilityOptIn,
        activeFamilyId: activeFamilyId,
      );
      final entity = model.toEntity();
      _cachedUser = entity;
      return Success(entity);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _remoteDataSource.signOut();
      _cachedUser = null;
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
