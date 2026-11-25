import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';

import '../../../../core/di/dependency_injection.dart';
import '../../../../core/drafts/local_draft_store.dart';
import '../../../../core/services/android_notification_bridge.dart';
import '../../../../core/services/native_alarm_scheduler_bridge.dart';
import '../../../../core/services/native_home_widget_bridge.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../domain/usecases/auth_usecases.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final WatchCurrentUserUseCase _watchCurrentUser;
  final SignInUseCase _signIn;
  final SignUpUseCase _signUp;
  final SignInWithGoogleUseCase _signInWithGoogle;
  final LinkGoogleAccountUseCase _linkGoogleAccount;
  final SendPasswordResetUseCase _sendPasswordReset;
  final SendEmailVerificationUseCase _sendEmailVerification;
  final ReloadCurrentUserUseCase _reloadCurrentUser;
  final UpdateUserProfileUseCase _updateUserProfile;
  final ChangePasswordUseCase _changePassword;
  final CompleteOnboardingUseCase _completeOnboarding;
  final UpdatePrivacySettingsUseCase _updatePrivacySettings;
  final SignOutUseCase _signOut;

  AuthBloc({
    required WatchCurrentUserUseCase watchCurrentUser,
    required SignInUseCase signIn,
    required SignUpUseCase signUp,
    required SignInWithGoogleUseCase signInWithGoogle,
    required LinkGoogleAccountUseCase linkGoogleAccount,
    required SendPasswordResetUseCase sendPasswordReset,
    required SendEmailVerificationUseCase sendEmailVerification,
    required ReloadCurrentUserUseCase reloadCurrentUser,
    required UpdateUserProfileUseCase updateUserProfile,
    required ChangePasswordUseCase changePassword,
    required CompleteOnboardingUseCase completeOnboarding,
    required UpdatePrivacySettingsUseCase updatePrivacySettings,
    required SignOutUseCase signOut,
  }) : _watchCurrentUser = watchCurrentUser,
       _signIn = signIn,
       _signUp = signUp,
       _signInWithGoogle = signInWithGoogle,
       _linkGoogleAccount = linkGoogleAccount,
       _sendPasswordReset = sendPasswordReset,
       _sendEmailVerification = sendEmailVerification,
       _reloadCurrentUser = reloadCurrentUser,
       _updateUserProfile = updateUserProfile,
       _changePassword = changePassword,
       _completeOnboarding = completeOnboarding,
       _updatePrivacySettings = updatePrivacySettings,
       _signOut = signOut,
       super(const AuthState()) {
    on<AuthSubscriptionRequested>(
      _onSubscriptionRequested,
      transformer: restartable(),
    );
    on<AuthSignInSubmitted>(_onSignInSubmitted, transformer: droppable());
    on<AuthSignUpSubmitted>(_onSignUpSubmitted, transformer: droppable());
    on<AuthGoogleSignInRequested>(
      _onGoogleSignInRequested,
      transformer: droppable(),
    );
    on<AuthGoogleLinkRequested>(
      _onGoogleLinkRequested,
      transformer: droppable(),
    );
    on<AuthPasswordResetRequested>(
      _onPasswordResetRequested,
      transformer: droppable(),
    );
    on<AuthEmailVerificationRequested>(
      _onEmailVerificationRequested,
      transformer: droppable(),
    );
    on<AuthUserReloadRequested>(
      _onUserReloadRequested,
      transformer: droppable(),
    );
    on<AuthProfileUpdateSubmitted>(
      _onProfileUpdateSubmitted,
      transformer: sequential(),
    );
    on<AuthPasswordChangeSubmitted>(
      _onPasswordChangeSubmitted,
      transformer: sequential(),
    );
    on<AuthOnboardingCompleted>(
      _onOnboardingCompleted,
      transformer: sequential(),
    );
    on<AuthAvailabilitySharingToggled>(
      _onAvailabilityToggled,
      transformer: sequential(),
    );
    on<AuthActiveFamilyChanged>(
      _onActiveFamilyChanged,
      transformer: sequential(),
    );
    on<AuthSignOutRequested>(_onSignOutRequested, transformer: sequential());
  }

  Future<void> _onSubscriptionRequested(
    AuthSubscriptionRequested event,
    Emitter<AuthState> emit,
  ) async {
    await emit.forEach(
      _watchCurrentUser(),
      onData: (user) {
        if (user == null) {
          UserBehaviorPrefs.clearSessionOnSignOut();
          LocalDraftStore.clearAllInMemoryCaches();
          return state.copyWith(
            status: AuthStatus.unauthenticated,
            clearUser: true,
            isSubmitting: false,
          );
        }
        UserBehaviorPrefs.bindActiveUser(user.id);
        return state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          isSubmitting: false,
          clearFailure: true,
        );
      },
    );
  }

  Future<void> _onSignInSubmitted(
    AuthSignInSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(
      state.copyWith(isSubmitting: true, clearFailure: true, clearInfo: true),
    );
    final result = await _signIn(
      SignInParams(email: event.email, password: event.password),
    );
    result.fold(
      (failure) => emit(state.copyWith(isSubmitting: false, failure: failure)),
      (user) {
        UserBehaviorPrefs.bindActiveUser(user.id);
        emit(
          state.copyWith(
            status: AuthStatus.authenticated,
            user: user,
            isSubmitting: false,
            clearFailure: true,
          ),
        );
      },
    );
  }

  Future<void> _onSignUpSubmitted(
    AuthSignUpSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(
      state.copyWith(isSubmitting: true, clearFailure: true, clearInfo: true),
    );
    final result = await _signUp(
      SignUpParams(
        email: event.email,
        password: event.password,
        confirmPassword: event.confirmPassword,
        fullName: event.fullName,
        phoneNumber: event.phoneNumber,
        acceptedTerms: event.acceptedTerms,
      ),
    );
    result.fold(
      (failure) => emit(state.copyWith(isSubmitting: false, failure: failure)),
      (user) {
        UserBehaviorPrefs.bindActiveUser(user.id);
        emit(
          state.copyWith(
            status: AuthStatus.authenticated,
            user: user,
            isSubmitting: false,
            clearFailure: true,
          ),
        );
      },
    );
  }

  Future<void> _onGoogleSignInRequested(
    AuthGoogleSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(
      state.copyWith(isSubmitting: true, clearFailure: true, clearInfo: true),
    );
    final result = await _signInWithGoogle(const NoParams());
    result.fold(
      (failure) => emit(state.copyWith(isSubmitting: false, failure: failure)),
      (user) {
        UserBehaviorPrefs.bindActiveUser(user.id);
        emit(
          state.copyWith(
            status: AuthStatus.authenticated,
            user: user,
            isSubmitting: false,
            clearFailure: true,
          ),
        );
      },
    );
  }

  Future<void> _onGoogleLinkRequested(
    AuthGoogleLinkRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(
      state.copyWith(isSubmitting: true, clearFailure: true, clearInfo: true),
    );
    final result = await _linkGoogleAccount(const NoParams());
    result.fold(
      (failure) => emit(state.copyWith(isSubmitting: false, failure: failure)),
      (updated) => emit(
        state.copyWith(
          isSubmitting: false,
          user: updated,
          clearFailure: true,
          infoMessage:
              'Đã liên kết thành công tài khoản Google với hồ sơ Life OS.',
        ),
      ),
    );
  }

  Future<void> _onPasswordResetRequested(
    AuthPasswordResetRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(
      state.copyWith(isSubmitting: true, clearFailure: true, clearInfo: true),
    );
    final result = await _sendPasswordReset(event.email);
    result.fold(
      (failure) => emit(state.copyWith(isSubmitting: false, failure: failure)),
      (_) => emit(
        state.copyWith(
          isSubmitting: false,
          infoMessage: 'Đã gửi liên kết đặt lại mật khẩu tới email của bạn.',
        ),
      ),
    );
  }

  Future<void> _onEmailVerificationRequested(
    AuthEmailVerificationRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(
      state.copyWith(isSubmitting: true, clearFailure: true, clearInfo: true),
    );
    final result = await _sendEmailVerification(const NoParams());
    result.fold(
      (failure) => emit(state.copyWith(isSubmitting: false, failure: failure)),
      (_) => emit(
        state.copyWith(
          isSubmitting: false,
          infoMessage:
              'Đã gửi email xác thực. Hãy kiểm tra hộp thư và bấm Xác nhận.',
        ),
      ),
    );
  }

  Future<void> _onUserReloadRequested(
    AuthUserReloadRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(
      state.copyWith(isSubmitting: true, clearFailure: true, clearInfo: true),
    );
    final result = await _reloadCurrentUser(const NoParams());
    result.fold(
      (failure) => emit(state.copyWith(isSubmitting: false, failure: failure)),
      (updated) => emit(
        state.copyWith(
          isSubmitting: false,
          user: updated,
          infoMessage: updated.emailVerified
              ? 'Email tài khoản của bạn đã được xác thực thành công!'
              : 'Đã làm mới trạng thái hồ sơ (Email đang chờ xác thực).',
        ),
      ),
    );
  }

  Future<void> _onProfileUpdateSubmitted(
    AuthProfileUpdateSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final currentUser = state.user;
    if (currentUser == null) return;
    emit(
      state.copyWith(isSubmitting: true, clearFailure: true, clearInfo: true),
    );
    final result = await _updateUserProfile(
      UpdateUserProfileParams(
        userId: currentUser.id,
        fullName: event.fullName,
        phoneNumber: event.phoneNumber,
        timezone: event.timezone,
      ),
    );
    result.fold(
      (failure) => emit(state.copyWith(isSubmitting: false, failure: failure)),
      (updated) => emit(
        state.copyWith(
          isSubmitting: false,
          user: updated,
          clearFailure: true,
          infoMessage: 'Đã lưu cập nhật thông tin hồ sơ cá nhân.',
        ),
      ),
    );
  }

  Future<void> _onPasswordChangeSubmitted(
    AuthPasswordChangeSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final currentUser = state.user;
    if (currentUser == null) return;
    emit(
      state.copyWith(isSubmitting: true, clearFailure: true, clearInfo: true),
    );
    final result = await _changePassword(
      ChangePasswordParams(
        userId: currentUser.id,
        currentPassword: event.currentPassword,
        newPassword: event.newPassword,
        confirmPassword: event.confirmPassword,
        requireCurrentPassword: currentUser.hasPasswordProvider,
      ),
    );
    result.fold(
      (failure) => emit(state.copyWith(isSubmitting: false, failure: failure)),
      (updated) => emit(
        state.copyWith(
          isSubmitting: false,
          user: updated,
          clearFailure: true,
          infoMessage: currentUser.hasPasswordProvider
              ? 'Đã đổi mật khẩu bảo mật thành công.'
              : 'Đã thiết lập mật khẩu đăng nhập bằng Email thành công.',
        ),
      ),
    );
  }

  Future<void> _onOnboardingCompleted(
    AuthOnboardingCompleted event,
    Emitter<AuthState> emit,
  ) async {
    final currentUser = state.user;
    if (currentUser == null) return;
    emit(state.copyWith(isSubmitting: true, clearFailure: true));
    final result = await _completeOnboarding(currentUser.id);
    result.fold(
      (failure) => emit(state.copyWith(isSubmitting: false, failure: failure)),
      (updated) => emit(state.copyWith(isSubmitting: false, user: updated)),
    );
  }

  Future<void> _onAvailabilityToggled(
    AuthAvailabilitySharingToggled event,
    Emitter<AuthState> emit,
  ) async {
    final currentUser = state.user;
    if (currentUser == null) return;
    emit(state.copyWith(clearFailure: true, clearInfo: true));
    final result = await _updatePrivacySettings(
      UpdatePrivacyParams(
        userId: currentUser.id,
        availabilityOptIn: event.enabled,
      ),
    );
    result.fold(
      (failure) => emit(state.copyWith(failure: failure, clearInfo: true)),
      (updated) => emit(state.copyWith(user: updated)),
    );
  }

  Future<void> _onActiveFamilyChanged(
    AuthActiveFamilyChanged event,
    Emitter<AuthState> emit,
  ) async {
    final currentUser = state.user;
    if (currentUser == null) return;
    emit(state.copyWith(clearFailure: true, clearInfo: true));
    final result = await _updatePrivacySettings(
      UpdatePrivacyParams(
        userId: currentUser.id,
        activeFamilyId: event.familyId,
      ),
    );
    result.fold(
      (failure) => emit(state.copyWith(failure: failure, clearInfo: true)),
      (updated) => emit(state.copyWith(user: updated)),
    );
  }

  Future<void> _onSignOutRequested(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _signOut(const NoParams());
    UserBehaviorPrefs.clearSessionOnSignOut();
    LocalDraftStore.clearAllInMemoryCaches();
    if (sl.isRegistered<NativeHomeWidgetBridge>()) {
      await sl<NativeHomeWidgetBridge>().clearWidgetsOnSignOut();
    }
    if (sl.isRegistered<AndroidNotificationBridge>()) {
      final notifBridge = sl<AndroidNotificationBridge>();
      await notifBridge.syncConsentConfig(
        enabled: false,
        allowedPackages: const <String>[],
        voiceSoundboxEnabled: false,
      );
      await notifBridge.clearAllQueuedNotifications();
    }
    await NativeAlarmSchedulerBridge.instance.clearAllAlarms();
    emit(
      state.copyWith(
        status: AuthStatus.unauthenticated,
        clearUser: true,
        isSubmitting: false,
        clearFailure: true,
        clearInfo: true,
      ),
    );
  }
}
