import 'package:equatable/equatable.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/user_entity.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

final class AuthState extends Equatable {
  final AuthStatus status;
  final UserEntity? user;
  final bool isSubmitting;
  final Failure? failure;
  final String? infoMessage;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.isSubmitting = false,
    this.failure,
    this.infoMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserEntity? user,
    bool clearUser = false,
    bool? isSubmitting,
    Failure? failure,
    bool clearFailure = false,
    String? infoMessage,
    bool clearInfo = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: clearFailure ? null : (failure ?? this.failure),
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
    );
  }

  @override
  List<Object?> get props => [status, user, isSubmitting, failure, infoMessage];
}
