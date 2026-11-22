import '../error/app_exception.dart';

abstract interface class UseCase<Output, Params> {
  Future<Result<Output>> call(Params params);
}

abstract interface class StreamUseCase<Output, Params> {
  Stream<Result<Output>> call(Params params);
}

final class NoParams {
  const NoParams();
}
