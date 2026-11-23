import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceCalendarInfo {
  final int deviceCalendarId;
  final String summary;
  final String accountName;
  final String accountType;
  final String colorHex;
  final bool isPrimary;
  final bool isReadOnly;
  final String timeZone;

  const DeviceCalendarInfo({
    required this.deviceCalendarId,
    required this.summary,
    this.accountName = '',
    this.accountType = '',
    this.colorHex = '#0B7A2A',
    this.isPrimary = false,
    this.isReadOnly = false,
    this.timeZone = 'Asia/Ho_Chi_Minh',
  });

  factory DeviceCalendarInfo.fromMap(Map<dynamic, dynamic> map) {
    return DeviceCalendarInfo(
      deviceCalendarId: (map['deviceCalendarId'] as num?)?.toInt() ?? 0,
      summary: (map['summary'] as String?)?.trim() ?? 'Lịch Thiết bị',
      accountName: (map['accountName'] as String?) ?? '',
      accountType: (map['accountType'] as String?) ?? '',
      colorHex: (map['colorHex'] as String?) ?? '#0B7A2A',
      isPrimary: (map['isPrimary'] as bool?) ?? false,
      isReadOnly: (map['isReadOnly'] as bool?) ?? false,
      timeZone: (map['timeZone'] as String?) ?? 'Asia/Ho_Chi_Minh',
    );
  }
}

class DeviceCalendarEventItem {
  final String instanceKey;
  final int deviceEventId;
  final int deviceCalendarId;
  final String title;
  final String? description;
  final String? location;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isAllDay;
  final String timeZone;
  final String colorHex;
  final String? rrule;
  final String? syncId;

  const DeviceCalendarEventItem({
    required this.instanceKey,
    required this.deviceEventId,
    required this.deviceCalendarId,
    required this.title,
    this.description,
    this.location,
    required this.startsAt,
    required this.endsAt,
    this.isAllDay = false,
    this.timeZone = 'Asia/Ho_Chi_Minh',
    this.colorHex = '#0B7A2A',
    this.rrule,
    this.syncId,
  });

  factory DeviceCalendarEventItem.fromMap(Map<dynamic, dynamic> map) {
    final startMs =
        (map['startsAtMs'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final endMs = (map['endsAtMs'] as num?)?.toInt() ?? (startMs + 3600000);
    final devEvId = (map['deviceEventId'] as num?)?.toInt() ?? 0;
    return DeviceCalendarEventItem(
      instanceKey: (map['instanceKey'] as String?) ?? '$devEvId',
      deviceEventId: devEvId,
      deviceCalendarId: (map['deviceCalendarId'] as num?)?.toInt() ?? 1,
      title: (map['title'] as String?)?.trim() ?? '(Không có tiêu đề)',
      description: map['description'] as String?,
      location: map['location'] as String?,
      startsAt: DateTime.fromMillisecondsSinceEpoch(startMs),
      endsAt: DateTime.fromMillisecondsSinceEpoch(endMs),
      isAllDay: (map['isAllDay'] as bool?) ?? false,
      timeZone: (map['timeZone'] as String?) ?? 'Asia/Ho_Chi_Minh',
      colorHex: (map['colorHex'] as String?) ?? '#0B7A2A',
      rrule: map['rrule'] as String?,
      syncId: map['syncId'] as String?,
    );
  }
}

abstract interface class DeviceCalendarDriver {
  bool get isSupportedPlatform;
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<List<DeviceCalendarInfo>> listCalendars();
  Future<List<DeviceCalendarEventItem>> listEvents({
    required DateTime windowStart,
    required DateTime windowEnd,
  });
  Future<int?> upsertEvent({
    int? deviceEventId,
    int? deviceCalendarId,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool isAllDay = false,
    String timeZone = 'Asia/Ho_Chi_Minh',
    String? rrule,
    int reminderMinutesBefore = 15,
  });
  Future<bool> deleteEvent(int deviceEventId);
}

class MethodChannelDeviceCalendarDriver implements DeviceCalendarDriver {
  static const MethodChannel _channel = MethodChannel(
    'vn.lifeos.app/device_calendar',
  );

  const MethodChannelDeviceCalendarDriver();

  @override
  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> hasPermission() async {
    if (!isSupportedPlatform) return false;
    try {
      final res = await _channel.invokeMethod<bool>('hasPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!isSupportedPlatform) return false;
    try {
      final res = await _channel.invokeMethod<bool>('requestPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<DeviceCalendarInfo>> listCalendars() async {
    if (!isSupportedPlatform) return const <DeviceCalendarInfo>[];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('listCalendars');
      if (raw == null) return const <DeviceCalendarInfo>[];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(DeviceCalendarInfo.fromMap)
          .where((c) => c.deviceCalendarId > 0)
          .toList();
    } catch (_) {
      return const <DeviceCalendarInfo>[];
    }
  }

  @override
  Future<List<DeviceCalendarEventItem>> listEvents({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    if (!isSupportedPlatform) return const <DeviceCalendarEventItem>[];
    try {
      final raw = await _channel
          .invokeMethod<List<dynamic>>('listEvents', <String, dynamic>{
            'windowStartMs': windowStart.millisecondsSinceEpoch,
            'windowEndMs': windowEnd.millisecondsSinceEpoch,
          });
      if (raw == null) return const <DeviceCalendarEventItem>[];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(DeviceCalendarEventItem.fromMap)
          .where((e) => e.deviceEventId > 0)
          .toList();
    } catch (_) {
      return const <DeviceCalendarEventItem>[];
    }
  }

  @override
  Future<int?> upsertEvent({
    int? deviceEventId,
    int? deviceCalendarId,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool isAllDay = false,
    String timeZone = 'Asia/Ho_Chi_Minh',
    String? rrule,
    int reminderMinutesBefore = 15,
  }) async {
    if (!isSupportedPlatform) return null;
    try {
      final res = await _channel
          .invokeMethod<num>('upsertEvent', <String, dynamic>{
            if (deviceEventId != null) 'deviceEventId': deviceEventId,
            if (deviceCalendarId != null) 'deviceCalendarId': deviceCalendarId,
            'title': title,
            'description': description,
            'location': location,
            'startsAtMs': startsAt.millisecondsSinceEpoch,
            'endsAtMs': endsAt.millisecondsSinceEpoch,
            'isAllDay': isAllDay,
            'timeZone': timeZone,
            'rrule': rrule,
            'reminderMinutesBefore': reminderMinutesBefore,
          });
      return res?.toInt();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> deleteEvent(int deviceEventId) async {
    if (!isSupportedPlatform) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'deleteEvent',
        <String, dynamic>{'deviceEventId': deviceEventId},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Bridge for reading and writing real events in the user's phone Calendar (`CalendarContract`).
class NativeDeviceCalendarBridge {
  static DeviceCalendarDriver _driver =
      const MethodChannelDeviceCalendarDriver();

  static const NativeDeviceCalendarBridge instance =
      NativeDeviceCalendarBridge._();

  const NativeDeviceCalendarBridge._();

  @visibleForTesting
  static void setDriverOverride(DeviceCalendarDriver? overrideDriver) {
    _driver = overrideDriver ?? const MethodChannelDeviceCalendarDriver();
  }

  bool get isSupportedPlatform => _driver.isSupportedPlatform;

  Future<bool> hasPermission() => _driver.hasPermission();

  Future<bool> requestPermission() => _driver.requestPermission();

  Future<List<DeviceCalendarInfo>> listCalendars() => _driver.listCalendars();

  Future<List<DeviceCalendarEventItem>> listEvents({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) => _driver.listEvents(windowStart: windowStart, windowEnd: windowEnd);

  Future<int?> upsertEvent({
    int? deviceEventId,
    int? deviceCalendarId,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool isAllDay = false,
    String timeZone = 'Asia/Ho_Chi_Minh',
    String? rrule,
    int reminderMinutesBefore = 15,
  }) => _driver.upsertEvent(
    deviceEventId: deviceEventId,
    deviceCalendarId: deviceCalendarId,
    title: title,
    description: description,
    location: location,
    startsAt: startsAt,
    endsAt: endsAt,
    isAllDay: isAllDay,
    timeZone: timeZone,
    rrule: rrule,
    reminderMinutesBefore: reminderMinutesBefore,
  );

  Future<bool> deleteEvent(int deviceEventId) =>
      _driver.deleteEvent(deviceEventId);
}
