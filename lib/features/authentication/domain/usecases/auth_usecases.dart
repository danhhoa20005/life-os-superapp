import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

final class SignUpParams {
  final String email;
  final String password;
  final String? confirmPassword;
  final String fullName;
  final String? phoneNumber;
  final bool acceptedTerms;

  const SignUpParams({
    required this.email,
    required this.password,
    this.confirmPassword,
    required this.fullName,
    this.phoneNumber,
    this.acceptedTerms = true,
  });
}

class SignUpUseCase implements UseCase<UserEntity, SignUpParams> {
  final AuthRepository _repository;
  const SignUpUseCase(this._repository);

  @override
  Future<Result<UserEntity>> call(SignUpParams params) async {
    final email = params.email.trim().toLowerCase();
    final name = params.fullName.trim();
    final phone = params.phoneNumber?.trim() ?? '';

    if (!params.acceptedTerms) {
      return const Err(
        ValidationFailure(
          message:
              'Vui lòng đồng ý với Chính sách Quyền riêng tư & Điều khoản sử dụng.',
        ),
      );
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return const Err(
        ValidationFailure(message: 'Vui lòng nhập địa chỉ email hợp lệ.'),
      );
    }
    if (name.length < 2) {
      return const Err(
        ValidationFailure(message: 'Họ và tên phải có ít nhất 2 ký tự.'),
      );
    }
    if (phone.isNotEmpty && !RegExp(r'^[0-9+\-\s]{9,15}$').hasMatch(phone)) {
      return const Err(
        ValidationFailure(
          message: 'Số điện thoại không hợp lệ (nhập 9–15 chữ số).',
        ),
      );
    }
    if (params.password.length < 8) {
      return const Err(
        ValidationFailure(message: 'Mật khẩu phải có ít nhất 8 ký tự.'),
      );
    }
    if (params.confirmPassword != null &&
        params.confirmPassword != params.password) {
      return const Err(
        ValidationFailure(message: 'Mật khẩu xác nhận không trùng khớp.'),
      );
    }
    return _repository.signUp(
      email: email,
      password: params.password,
      fullName: name,
      phoneNumber: phone.isEmpty ? null : phone,
    );
  }
}

final class SignInParams {
  final String email;
  final String password;

  const SignInParams({required this.email, required this.password});
}

class SignInUseCase implements UseCase<UserEntity, SignInParams> {
  final AuthRepository _repository;
  const SignInUseCase(this._repository);

  @override
  Future<Result<UserEntity>> call(SignInParams params) async {
    final email = params.email.trim().toLowerCase();
    if (email.isEmpty || params.password.isEmpty) {
      return const Err(
        ValidationFailure(message: 'Vui lòng nhập đầy đủ email và mật khẩu.'),
      );
    }
    return _repository.signIn(email: email, password: params.password);
  }
}

class SignInWithGoogleUseCase implements UseCase<UserEntity, NoParams> {
  final AuthRepository _repository;
  const SignInWithGoogleUseCase(this._repository);

  @override
  Future<Result<UserEntity>> call(NoParams params) {
    return _repository.signInWithGoogle();
  }
}

class LinkGoogleAccountUseCase implements UseCase<UserEntity, NoParams> {
  final AuthRepository _repository;
  const LinkGoogleAccountUseCase(this._repository);

  @override
  Future<Result<UserEntity>> call(NoParams params) {
    return _repository.linkGoogleAccount();
  }
}

class SendPasswordResetUseCase implements UseCase<void, String> {
  final AuthRepository _repository;
  const SendPasswordResetUseCase(this._repository);

  @override
  Future<Result<void>> call(String email) async {
    final clean = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(clean)) {
      return const Err(
        ValidationFailure(
          message: 'Email nhận liên kết đặt lại mật khẩu không hợp lệ.',
        ),
      );
    }
    return _repository.sendPasswordReset(email: clean);
  }
}

class SendEmailVerificationUseCase implements UseCase<void, NoParams> {
  final AuthRepository _repository;
  const SendEmailVerificationUseCase(this._repository);

  @override
  Future<Result<void>> call(NoParams params) {
    return _repository.sendEmailVerification();
  }
}

class ReloadCurrentUserUseCase implements UseCase<UserEntity, NoParams> {
  final AuthRepository _repository;
  const ReloadCurrentUserUseCase(this._repository);

  @override
  Future<Result<UserEntity>> call(NoParams params) {
    return _repository.reloadCurrentUser();
  }
}

final class UpdateUserProfileParams {
  final String userId;
  final String fullName;
  final String? phoneNumber;
  final String? timezone;

  const UpdateUserProfileParams({
    required this.userId,
    required this.fullName,
    this.phoneNumber,
    this.timezone,
  });
}

class UpdateUserProfileUseCase
    implements UseCase<UserEntity, UpdateUserProfileParams> {
  final AuthRepository _repository;
  const UpdateUserProfileUseCase(this._repository);

  @override
  Future<Result<UserEntity>> call(UpdateUserProfileParams params) async {
    final cleanName = params.fullName.trim();
    final cleanPhone = params.phoneNumber?.trim() ?? '';
    if (cleanName.length < 2) {
      return const Err(
        ValidationFailure(message: 'Họ và tên phải có ít nhất 2 ký tự.'),
      );
    }
    if (cleanPhone.isNotEmpty &&
        !RegExp(r'^[0-9+\-\s]{9,15}$').hasMatch(cleanPhone)) {
      return const Err(
        ValidationFailure(
          message: 'Số điện thoại không hợp lệ (nhập 9–15 chữ số).',
        ),
      );
    }
    return _repository.updateUserProfile(
      userId: params.userId,
      fullName: cleanName,
      phoneNumber: params.phoneNumber,
      timezone: params.timezone,
    );
  }
}

final class ChangePasswordParams {
  final String userId;
  final String? currentPassword;
  final String newPassword;
  final String confirmPassword;
  final bool requireCurrentPassword;

  const ChangePasswordParams({
    required this.userId,
    this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
    this.requireCurrentPassword = true,
  });
}

class ChangePasswordUseCase
    implements UseCase<UserEntity, ChangePasswordParams> {
  final AuthRepository _repository;
  const ChangePasswordUseCase(this._repository);

  @override
  Future<Result<UserEntity>> call(ChangePasswordParams params) async {
    if (params.requireCurrentPassword &&
        (params.currentPassword ?? '').isEmpty) {
      return const Err(
        ValidationFailure(
          message: 'Vui lòng nhập mật khẩu hiện tại để xác minh.',
        ),
      );
    }
    if (params.newPassword.length < 8) {
      return const Err(
        ValidationFailure(message: 'Mật khẩu mới phải có ít nhất 8 ký tự.'),
      );
    }
    if (params.newPassword != params.confirmPassword) {
      return const Err(
        ValidationFailure(
          message: 'Mật khẩu mới và xác nhận không trùng khớp.',
        ),
      );
    }
    return _repository.changePassword(
      userId: params.userId,
      currentPassword: params.currentPassword,
      newPassword: params.newPassword,
    );
  }
}

class CompleteOnboardingUseCase implements UseCase<UserEntity, String> {
  final AuthRepository _repository;
  const CompleteOnboardingUseCase(this._repository);

  @override
  Future<Result<UserEntity>> call(String userId) {
    return _repository.completeOnboarding(userId: userId);
  }
}

final class UpdatePrivacyParams {
  final String userId;
  final bool? availabilityOptIn;
  final String? activeFamilyId;

  const UpdatePrivacyParams({
    required this.userId,
    this.availabilityOptIn,
    this.activeFamilyId,
  });
}

class UpdatePrivacySettingsUseCase
    implements UseCase<UserEntity, UpdatePrivacyParams> {
  final AuthRepository _repository;
  const UpdatePrivacySettingsUseCase(this._repository);

  @override
  Future<Result<UserEntity>> call(UpdatePrivacyParams params) {
    return _repository.updatePrivacySettings(
      userId: params.userId,
      availabilityOptIn: params.availabilityOptIn,
      activeFamilyId: params.activeFamilyId,
    );
  }
}

class SignOutUseCase implements UseCase<void, NoParams> {
  final AuthRepository _repository;
  const SignOutUseCase(this._repository);

  @override
  Future<Result<void>> call(NoParams params) {
    return _repository.signOut();
  }
}

class WatchCurrentUserUseCase {
  final AuthRepository _repository;
  const WatchCurrentUserUseCase(this._repository);

  Stream<UserEntity?> call() => _repository.watchCurrentUser();
}
