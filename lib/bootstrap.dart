import 'dart:async';
import 'dart:developer' as developer;

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_bloc_observer.dart';
import 'app/config/firebase_config.dart';
import 'core/di/dependency_injection.dart';
import 'core/security/bank_notification_parser.dart';

Future<void> bootstrap() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      Bloc.observer = const AppBlocObserver();
      await FirebaseConfig.initialize();
      await configureDependencies();
      runApp(const LifeOsApp());
    },
    (error, stackTrace) {
      developer.log(
        OtpRedactor.redact('Uncaught zone error: $error'),
        name: 'LifeOS.Bootstrap',
      );
    },
  );
}
