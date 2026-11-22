import 'dart:developer' as developer;
import 'package:bloc/bloc.dart';
import '../../core/security/bank_notification_parser.dart';

/// Application-wide BLoC observer with automatic PII/OTP redaction.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    developer.log(
      OtpRedactor.redact('Event: ${bloc.runtimeType} -> ${event.runtimeType}'),
      name: 'LifeOS.Bloc',
    );
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    developer.log(
      OtpRedactor.redact('BlocError in ${bloc.runtimeType}: $error'),
      name: 'LifeOS.Bloc',
      error: OtpRedactor.redact(error.toString()),
    );
    super.onError(bloc, error, stackTrace);
  }
}
