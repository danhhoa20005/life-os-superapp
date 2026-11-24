import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum LifeOsPermissionKind {
  notifications,
  microphone,
  calendar,
  exactAlarm,
  batteryUnrestricted,
  bankNotificationListener,
}

/// Immutable snapshot of all OS permissions & system capabilities used by LifeOS.
final class AppPermissionsSnapshot extends Equatable {
  final bool notifications;
  final bool microphone;
  final bool calendar;
  final bool exactAlarm;
  final bool batteryUnrestricted;
  final bool bankNotificationListener;

  const AppPermissionsSnapshot({
    required this.notifications,
    required this.microphone,
    required this.calendar,
    required this.exactAlarm,
    required this.batteryUnrestricted,
    required this.bankNotificationListener,
  });

  static const AppPermissionsSnapshot allGranted = AppPermissionsSnapshot(
    notifications: true,
    microphone: true,
    calendar: true,
    exactAlarm: true,
    batteryUnrestricted: true,
    bankNotificationListener: true,
  );

  static const AppPermissionsSnapshot allMissing = AppPermissionsSnapshot(
    notifications: false,
    microphone: false,
    calendar: false,
    exactAlarm: false,
    batteryUnrestricted: false,
    bankNotificationListener: false,
  );

  factory AppPermissionsSnapshot.fromMap(Map<Object?, Object?> raw) {
    return AppPermissionsSnapshot(
      notifications: raw['notifications'] == true,
      microphone: raw['microphone'] == true,
      calendar: raw['calendar'] == true,
      exactAlarm: raw['exactAlarm'] == true,
      batteryUnrestricted: raw['batteryUnrestricted'] == true,
      bankNotificationListener: raw['bankNotificationListener'] == true,
    );
  }

  bool isGranted(LifeOsPermissionKind kind) => switch (kind) {
    LifeOsPermissionKind.notifications => notifications,
    LifeOsPermissionKind.microphone => microphone,
    LifeOsPermissionKind.calendar => calendar,
    LifeOsPermissionKind.exactAlarm => exactAlarm,
    LifeOsPermissionKind.batteryUnrestricted => batteryUnrestricted,
    LifeOsPermissionKind.bankNotificationListener => bankNotificationListener,
  };

  int get essentialGrantedCount =>
      (notifications ? 1 : 0) + (microphone ? 1 : 0) + (calendar ? 1 : 0);

  bool get isAllEssentialGranted => notifications && microphone && calendar;

  int get advancedGrantedCount =>
      (exactAlarm ? 1 : 0) +
      (batteryUnrestricted ? 1 : 0) +
      (bankNotificationListener ? 1 : 0);

  int get totalGrantedCount => essentialGrantedCount + advancedGrantedCount;

  bool get isAllGranted => totalGrantedCount == 6;

  AppPermissionsSnapshot copyWith({
    bool? notifications,
    bool? microphone,
    bool? calendar,
    bool? exactAlarm,
    bool? batteryUnrestricted,
    bool? bankNotificationListener,
  }) {
    return AppPermissionsSnapshot(
      notifications: notifications ?? this.notifications,
      microphone: microphone ?? this.microphone,
      calendar: calendar ?? this.calendar,
      exactAlarm: exactAlarm ?? this.exactAlarm,
      batteryUnrestricted: batteryUnrestricted ?? this.batteryUnrestricted,
      bankNotificationListener:
          bankNotificationListener ?? this.bankNotificationListener,
    );
  }

  @override
  List<Object?> get props => [
    notifications,
    microphone,
    calendar,
    exactAlarm,
    batteryUnrestricted,
    bankNotificationListener,
  ];
}

abstract interface class PermissionsDriver {
  bool get isSupportedPlatform;
  Future<AppPermissionsSnapshot> checkAll();
  Future<AppPermissionsSnapshot> requestEssential();
  Future<AppPermissionsSnapshot> requestSingle(LifeOsPermissionKind kind);
  Future<void> openAppSettings();
}

class MethodChannelPermissionsDriver implements PermissionsDriver {
  static const MethodChannel _channel = MethodChannel(
    'vn.lifeos.app/permissions',
  );

  const MethodChannelPermissionsDriver();

  @override
  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<AppPermissionsSnapshot> checkAll() async {
    if (!isSupportedPlatform) return AppPermissionsSnapshot.allGranted;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'checkAll',
      );
      if (raw == null) return AppPermissionsSnapshot.allGranted;
      return AppPermissionsSnapshot.fromMap(raw);
    } on MissingPluginException {
      return AppPermissionsSnapshot.allGranted;
    } catch (_) {
      return AppPermissionsSnapshot.allGranted;
    }
  }

  @override
  Future<AppPermissionsSnapshot> requestEssential() async {
    if (!isSupportedPlatform) return AppPermissionsSnapshot.allGranted;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'requestEssential',
      );
      if (raw == null) return AppPermissionsSnapshot.allGranted;
      return AppPermissionsSnapshot.fromMap(raw);
    } on MissingPluginException {
      return AppPermissionsSnapshot.allGranted;
    } catch (_) {
      return checkAll();
    }
  }

  @override
  Future<AppPermissionsSnapshot> requestSingle(
    LifeOsPermissionKind kind,
  ) async {
    if (!isSupportedPlatform) return AppPermissionsSnapshot.allGranted;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'requestSingle',
        <String, dynamic>{'kind': kind.name},
      );
      if (raw == null) return AppPermissionsSnapshot.allGranted;
      return AppPermissionsSnapshot.fromMap(raw);
    } on MissingPluginException {
      return AppPermissionsSnapshot.allGranted;
    } catch (_) {
      return checkAll();
    }
  }

  @override
  Future<void> openAppSettings() async {
    if (!isSupportedPlatform) return;
    try {
      await _channel.invokeMethod<Object?>(
        'requestSingle',
        const <String, dynamic>{'kind': 'appSettings'},
      );
    } catch (_) {}
  }
}

/// Unified permission inspection & request coordinator for LifeOS.
class NativePermissionsService {
  static PermissionsDriver _driver = const MethodChannelPermissionsDriver();

  static const NativePermissionsService instance = NativePermissionsService._();

  const NativePermissionsService._();

  @visibleForTesting
  static void setDriverOverride(PermissionsDriver? driver) {
    _driver = driver ?? const MethodChannelPermissionsDriver();
  }

  bool get isSupportedPlatform => _driver.isSupportedPlatform;

  Future<AppPermissionsSnapshot> checkAll() => _driver.checkAll();

  Future<AppPermissionsSnapshot> requestEssential() =>
      _driver.requestEssential();

  Future<AppPermissionsSnapshot> requestSingle(LifeOsPermissionKind kind) =>
      _driver.requestSingle(kind);

  Future<void> openAppSettings() => _driver.openAppSettings();
}
