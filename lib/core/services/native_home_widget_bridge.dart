import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeHomeWidgetBridge {
  static const MethodChannel _channel = MethodChannel(
    'vn.lifeos.app/home_widgets',
  );

  static const String actionVoiceCapture =
      'vn.lifeos.app.WIDGET_ACTION_VOICE_CAPTURE';
  static const String actionVoiceSplit =
      'vn.lifeos.app.WIDGET_ACTION_VOICE_SPLIT';
  static const String actionOpenToday =
      'vn.lifeos.app.WIDGET_ACTION_OPEN_TODAY';
  static const String actionOpenFinance =
      'vn.lifeos.app.WIDGET_ACTION_OPEN_FINANCE';
  static const String actionOpenFamily =
      'vn.lifeos.app.WIDGET_ACTION_OPEN_FAMILY';

  final StreamController<String> _actionController =
      StreamController<String>.broadcast();
  bool _handlerBound = false;

  NativeHomeWidgetBridge();

  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _hasServicesBinding {
    try {
      ServicesBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  Stream<String> get widgetActions {
    if (isSupportedPlatform && _hasServicesBinding && !_handlerBound) {
      _handlerBound = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onWidgetAction' && call.arguments is String) {
          _actionController.add(call.arguments as String);
        }
      });
    }
    return _actionController.stream;
  }

  Future<String?> consumePendingWidgetAction() async {
    if (!isSupportedPlatform || !_hasServicesBinding) return null;
    try {
      return await _channel.invokeMethod<String>('consumePendingWidgetAction');
    } catch (_) {
      return null;
    }
  }

  Future<bool> requestPinWidget(String widgetKind) async {
    if (!isSupportedPlatform || !_hasServicesBinding) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'requestPinWidget',
        <String, dynamic>{'widgetKind': widgetKind},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> syncWidgets({
    required String netWorth,
    required String monthlyIncome,
    required String monthlyExpense,
    required String todayExpense,
    required String safeDaily,
    required String wealthBadge,
    required String groupTitle,
    required String groupStatus,
    required String runwayLabel,
    required int dailyUsedPct,
  }) async {
    if (!isSupportedPlatform || !_hasServicesBinding) return;
    try {
      await _channel.invokeMethod<void>('updateWidgets', <String, dynamic>{
        'netWorth': netWorth,
        'monthlyIncome': monthlyIncome,
        'monthlyExpense': monthlyExpense,
        'todayExpense': todayExpense,
        'safeDaily': safeDaily,
        'wealthBadge': wealthBadge,
        'groupTitle': groupTitle,
        'groupStatus': groupStatus,
        'runwayLabel': runwayLabel,
        'dailyUsedPct': dailyUsedPct,
      });
    } catch (_) {}
  }
}
