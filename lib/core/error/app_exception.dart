import 'failure.dart';

class AppException implements Exception {
  final String code;
  final String message;

  const AppException({required this.code, required this.message});

  @override
  String toString() => 'AppException($code): $message';
}

sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Err<T>;

  R fold<R>(
    R Function(Failure failure) onFailure,
    R Function(T value) onSuccess,
  ) {
    final self = this;
    if (self is Success<T>) {
      return onSuccess(self.value);
    }
    return onFailure((self as Err<T>).failure);
  }
}

final class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

final class Err<T> extends Result<T> {
  final Failure failure;
  const Err(this.failure);
}
