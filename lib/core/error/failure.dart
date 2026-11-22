import 'package:equatable/equatable.dart';

sealed class Failure extends Equatable {
  final String message;
  final String code;

  const Failure({required this.message, required this.code});

  @override
  List<Object?> get props => [code, message];
}

final class NetworkFailure extends Failure {
  const NetworkFailure({
    super.message = 'Không thể kết nối mạng. Vui lòng kiểm tra kết nối của bạn.',
    super.code = 'NETWORK_FAILURE',
  });
}

final class AuthenticationFailure extends Failure {
  const AuthenticationFailure({
    required super.message,
    super.code = 'AUTH_FAILURE',
  });
}

final class PermissionDeniedFailure extends Failure {
  const PermissionDeniedFailure({
    super.message = 'Bạn không có quyền truy cập hoặc thực hiện thao tác trên dữ liệu này.',
    super.code = 'PERMISSION_DENIED',
  });
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure({
    super.message = 'Không tìm thấy dữ liệu yêu cầu.',
    super.code = 'NOT_FOUND',
  });
}

final class ValidationFailure extends Failure {
  const ValidationFailure({
    required super.message,
    super.code = 'VALIDATION_FAILURE',
  });
}

final class ConflictFailure extends Failure {
  const ConflictFailure({
    required super.message,
    super.code = 'CONFLICT_FAILURE',
  });
}

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure({
    super.message = 'Đã xảy ra lỗi ngoài dự kiến. Vui lòng thử lại sau.',
    super.code = 'UNEXPECTED_FAILURE',
  });
}
