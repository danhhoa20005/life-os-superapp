import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../core/di/dependency_injection.dart';
import '../core/motion/lifeos_motion_scope.dart';
import '../core/widgets/lifeos_top_toast.dart';
import '../features/app_update/presentation/bloc/app_update_bloc.dart';
import '../features/authentication/presentation/bloc/auth_bloc.dart';
import '../features/authentication/presentation/bloc/auth_event.dart';
import '../features/authentication/presentation/bloc/auth_state.dart';
import 'app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_bloc.dart';

class LifeOsApp extends StatefulWidget {
  const LifeOsApp({super.key});

  @override
  State<LifeOsApp> createState() => _LifeOsAppState();
}

class _LifeOsAppState extends State<LifeOsApp> {
  late final AuthBloc _authBloc;
  late final ThemeBloc _themeBloc;
  late final AppUpdateBloc _appUpdateBloc;
  late final BlocRouterRefreshStream _routerRefresh;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authBloc = sl<AuthBloc>()..add(const AuthSubscriptionRequested());
    _themeBloc = sl<ThemeBloc>()..add(const ThemeHydratedFromDisk());
    _appUpdateBloc = sl<AppUpdateBloc>()
      ..add(const AppUpdateCheckRequested(silent: true));
    _routerRefresh = BlocRouterRefreshStream(_authBloc.stream);
    _router = createAppRouter(_authBloc, _routerRefresh);
  }

  @override
  void dispose() {
    _routerRefresh.dispose();
    _router.dispose();
    _authBloc.close();
    _themeBloc.close();
    _appUpdateBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: _authBloc),
        BlocProvider<ThemeBloc>.value(value: _themeBloc),
        BlocProvider<AppUpdateBloc>.value(value: _appUpdateBloc),
      ],
      child: BlocListener<AuthBloc, AuthState>(
        listenWhen: (prev, curr) =>
            prev.status != curr.status &&
            curr.status == AuthStatus.authenticated,
        listener: (_, __) {
          _appUpdateBloc.add(const AppUpdateCheckRequested(silent: true));
        },
        child: BlocBuilder<ThemeBloc, ThemeState>(
          builder: (context, themeState) {
            return MaterialApp.router(
              title: 'Life OS — Quản lý Cuộc sống & Gia đình',
              debugShowCheckedModeBanner: false,
              themeMode: themeState.themeMode,
              theme: AppTheme.light(
                highContrast: themeState.highContrast,
                compactDensity: themeState.compactDensity,
              ),
              darkTheme: AppTheme.dark(
                highContrast: themeState.highContrast,
                compactDensity: themeState.compactDensity,
              ),
              highContrastTheme: AppTheme.light(
                highContrast: true,
                compactDensity: themeState.compactDensity,
              ),
              highContrastDarkTheme: AppTheme.dark(
                highContrast: true,
                compactDensity: themeState.compactDensity,
              ),
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                final osScale = mq.textScaler.scale(1.0);
                final effectiveScale = osScale > 1.0
                    ? math.max(osScale, themeState.textScale)
                    : themeState.textScale;
                return MediaQuery(
                  data: mq.copyWith(
                    textScaler: TextScaler.linear(effectiveScale),
                  ),
                  child: LifeOsMotionHost(
                    userMode: themeState.motionMode,
                    child: LifeOsTopToastHost(
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                );
              },
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('vi', 'VN'), Locale('en', 'US')],
              routerConfig: _router,
            );
          },
        ),
      ),
    );
  }
}
