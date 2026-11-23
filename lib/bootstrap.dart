import 'dart:async';
import 'dart:developer' as developer;

import 'package:bloc/bloc.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_bloc_observer.dart';
import 'app/config/firebase_config.dart';
import 'core/di/dependency_injection.dart';
import 'core/security/bank_notification_parser.dart';
import 'core/services/fcm_banking_messaging_service.dart';

Future<void> bootstrap() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      Bloc.observer = const AppBlocObserver();
      await FirebaseConfig.initialize();
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        FirebaseMessaging.onBackgroundMessage(
          lifeOsFirebaseMessagingBackgroundHandler,
        );
      }
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
