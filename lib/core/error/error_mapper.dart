import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app_exception.dart';
import 'failure.dart';

abstract final class ErrorMapper {
  static Failure map(Object error) {
    if (error is Failure) return error;

    if (error is AppException) {
      return switch (error.code) {
        'VALIDATION_FAILURE' => ValidationFailure(message: error.message),
        'NOT_FOUND' => NotFoundFailure(message: error.message),
        'CONFLICT_FAILURE' => ConflictFailure(message: error.message),
        'PERMISSION_DENIED' => PermissionDeniedFailure(message: error.message),
        'AUTH_CANCELED' || 'AUTH_FAILURE' => AuthenticationFailure(message: error.message),
        _ => UnexpectedFailure(message: error.message, code: error.code),
      };
    }

    if (error is GoogleSignInException) {
      return switch (error.code) {
        GoogleSignInExceptionCode.canceled =>
          const AuthenticationFailure(message: 'Bạn đã hủy đăng nhập bằng Google.'),
        GoogleSignInExceptionCode.interrupted => const AuthenticationFailure(
            message: 'Phiên đăng nhập Google bị gián đoạn. Vui lòng thử lại.',
          ),
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          const AuthenticationFailure(
            message:
                'Chưa hoàn tất cấu hình OAuth SHA-1 trên Firebase Cloud cho Google Sign-In.',
          ),
        _ => AuthenticationFailure(
            message: error.description ?? 'Đăng nhập Google không thành công. Vui lòng thử lại.',
          ),
      };
    }

    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-email' => const ValidationFailure(message: 'Địa chỉ email không đúng định dạng.'),
        'user-disabled' => const AuthenticationFailure(message: 'Tài khoản này đã bị vô hiệu hóa.'),
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          const AuthenticationFailure(message: 'Email hoặc mật khẩu không chính xác.'),
        'email-already-in-use' =>
          const ConflictFailure(message: 'Email này đã được sử dụng cho một tài khoản khác.'),
        'account-exists-with-different-credential' => const ConflictFailure(
            message:
                'Email này đã đăng ký bằng mật khẩu. Hãy đăng nhập rồi liên kết Google trong Hồ sơ.',
          ),
        'credential-already-in-use' => const ConflictFailure(
            message: 'Tài khoản Google này đã được liên kết với một tài khoản khác.',
          ),
        'provider-already-linked' => const ConflictFailure(
            message: 'Phương thức đăng nhập này đã được liên kết sẵn.',
          ),
        'weak-password' =>
          const ValidationFailure(message: 'Mật khẩu quá yếu (tối thiểu 8 ký tự).'),
        'requires-recent-login' => const AuthenticationFailure(
            message:
                'Vì lý do bảo mật, vui lòng đăng xuất và đăng nhập lại trước khi thực hiện thao tác này.',
          ),
        'operation-not-allowed' => const AuthenticationFailure(
            message:
                'Phương thức đăng nhập này chưa được kích hoạt trong Firebase Authentication.',
          ),
        'popup-closed-by-user' || 'web-context-canceled' || 'canceled' =>
          const AuthenticationFailure(message: 'Bạn đã hủy cửa sổ đăng nhập Google.'),
        'network-request-failed' => const NetworkFailure(),
        'too-many-requests' => const AuthenticationFailure(
            message: 'Quá nhiều lần thử thất bại. Vui lòng đợi ít phút rồi thử lại.',
          ),
        _ => (error.message != null && error.message!.contains('CONFIGURATION_NOT_FOUND'))
            ? const AuthenticationFailure(
                message:
                    'Dự án Cloud life-os-vn-2026 cần bật nút "Get started" 1 lần tại Firebase Console (Authentication → Sign-in method → Bật Email/Password & Google).',
              )
            : AuthenticationFailure(
                message: error.message ?? 'Xác thực không thành công. Vui lòng thử lại.',
              ),
      };
    }

    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' || 'unauthenticated' => const PermissionDeniedFailure(),
        'not-found' => const NotFoundFailure(),
        'already-exists' || 'aborted' => const ConflictFailure(
            message: 'Dữ liệu vừa được cập nhật ở phiên khác. Vui lòng thử lại.',
          ),
        'unavailable' || 'deadline-exceeded' => const NetworkFailure(),
        'invalid-argument' => ValidationFailure(
            message: error.message ?? 'Dữ liệu gửi lên không hợp lệ.',
          ),
        _ => const UnexpectedFailure(),
      };
    }

    if (error is SocketException) {
      return const NetworkFailure();
    }

    return const UnexpectedFailure();
  }
}
