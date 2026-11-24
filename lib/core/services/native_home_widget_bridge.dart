import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Structured action performed directly on an outside Android Home Screen Widget
/// (`LifeOsWidgetActionReceiver` or `LifeOsWidgetQuickOverlayActivity`) while the app was closed or backgrounded.
class QueuedHomeWidgetCommand {
  final String id;
  final String kind;
  final String commandText;
  final String label;
  final int amountMinor;
  final int memberCount;
  final String targetCommandId;
  final int createdAtEpochMs;

  const QueuedHomeWidgetCommand({
    required this.id,
    required this.kind,
    required this.commandText,
    this.label = '',
    this.amountMinor = 0,
    this.memberCount = 3,
    this.targetCommandId = '',
    this.createdAtEpochMs = 0,
  });

  factory QueuedHomeWidgetCommand.fromMap(Map<dynamic, dynamic> map) {
    return QueuedHomeWidgetCommand(
      id: (map['id'] as String?) ?? '',
      kind: (map['kind'] as String?) ?? 'expense',
      commandText: (map['commandText'] as String?) ?? '',
      label: (map['label'] as String?) ?? '',
      amountMinor: (map['amountMinor'] as num?)?.toInt() ?? 0,
      memberCount: (map['memberCount'] as num?)?.toInt() ?? 3,
      targetCommandId: (map['targetCommandId'] as String?) ?? '',
      createdAtEpochMs: (map['createdAtEpochMs'] as num?)?.toInt() ?? 0,
    );
  }
}

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
  final StreamController<void> _bgCommandController =
      StreamController<void>.broadcast();
  bool _handlerBound = false;

  final List<QueuedHomeWidgetCommand> _simulatedQueue =
      <QueuedHomeWidgetCommand>[];
  Map<String, dynamic>? _lastSyncedPayload;

  NativeHomeWidgetBridge();

  bool get isSupportedPlatform =>
      !kIsWeb && Platform.isAndroid;

  bool get _hasServicesBinding {
    try {
      ServicesBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _ensureMethodCallHandlerBound() {
    if (isSupportedPlatform && _hasServicesBinding && !_handlerBound) {
      _handlerBound = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onWidgetAction' && call.arguments is String) {
          _actionController.add(call.arguments as String);
        } else if (call.method == 'onBackgroundWidgetCommand') {
          _bgCommandController.add(null);
        }
      });
    }
  }

  Stream<String> get widgetActions {
    _ensureMethodCallHandlerBound();
    return _actionController.stream;
  }

  Stream<void> get backgroundCommandSignals {
    _ensureMethodCallHandlerBound();
    return _bgCommandController.stream;
  }

  @visibleForTesting
  Map<String, dynamic>? get debugLastSyncedPayload => _lastSyncedPayload;

  /// Simulates an outside Home-Screen widget tap (BroadcastReceiver / Floating Overlay)
  /// during automated widget/integration tests.
  @visibleForTesting
  void simulateHomeScreenWidgetCommand(
    QueuedHomeWidgetCommand command, {
    bool notifyLiveListener = true,
  }) {
    _simulatedQueue.add(command);
    if (notifyLiveListener) {
      _bgCommandController.add(null);
    }
  }

  Future<List<QueuedHomeWidgetCommand>> drainQueuedWidgetCommands() async {
    final results = <QueuedHomeWidgetCommand>[];
    if (_simulatedQueue.isNotEmpty) {
      results.addAll(_simulatedQueue);
      _simulatedQueue.clear();
    }
    if (!isSupportedPlatform || !_hasServicesBinding) {
      return results;
    }
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'drainQueuedWidgetCommands',
      );
      if (raw != null) {
        for (final item in raw) {
          if (item is Map) {
            results.add(QueuedHomeWidgetCommand.fromMap(item));
          }
        }
      }
    } catch (_) {}
    return results;
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
    int? netWorthMinor,
    int? monthlyIncomeMinor,
    int? monthlyExpenseMinor,
    int? todayExpenseMinor,
    int? safeDailyMinor,
    int? groupMemberCount,
    bool? hideBalances,
  }) async {
    final payload = <String, dynamic>{
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
      if (netWorthMinor != null) 'netWorthMinor': netWorthMinor,
      if (monthlyIncomeMinor != null) 'monthlyIncomeMinor': monthlyIncomeMinor,
      if (monthlyExpenseMinor != null)
        'monthlyExpenseMinor': monthlyExpenseMinor,
      if (todayExpenseMinor != null) 'todayExpenseMinor': todayExpenseMinor,
      if (safeDailyMinor != null) 'safeDailyMinor': safeDailyMinor,
      if (groupMemberCount != null) 'groupMemberCount': groupMemberCount,
      if (hideBalances != null) 'hideBalances': hideBalances,
    };
    _lastSyncedPayload = payload;
    if (!isSupportedPlatform || !_hasServicesBinding) return;
    try {
      await _channel.invokeMethod<void>('updateWidgets', payload);
    } catch (_) {}
  }
}
