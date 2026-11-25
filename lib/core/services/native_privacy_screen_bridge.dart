import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class PrivacyScreenDriver {
  bool get isSupportedPlatform;
  Future<bool> setPrivacyScreenEnabled(bool enabled);
}

class MethodChannelPrivacyScreenDriver implements PrivacyScreenDriver {
  static const MethodChannel _channel = MethodChannel(
    'vn.lifeos.app/privacy_screen',
  );

  const MethodChannelPrivacyScreenDriver();

  @override
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

  @override
  Future<bool> setPrivacyScreenEnabled(bool enabled) async {
    if (!isSupportedPlatform || !_hasServicesBinding) {
      return false;
    }
    try {
      final applied = await _channel.invokeMethod<bool>(
        'setPrivacyScreenEnabled',
        <String, dynamic>{'enabled': enabled},
      );
      return applied ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// Bridge controlling Android `FLAG_SECURE` + API 33+ `setRecentsScreenshotEnabled`
/// to prevent sensitive financial balances from leaking in Recent Apps snapshots.
class NativePrivacyScreenBridge {
  static const NativePrivacyScreenBridge instance =
      NativePrivacyScreenBridge();
  static PrivacyScreenDriver _driver = const MethodChannelPrivacyScreenDriver();
  static bool _isEnabled = false;

  const NativePrivacyScreenBridge();

  @visibleForTesting
  static void setDriverOverride(PrivacyScreenDriver? overrideDriver) {
    _driver = overrideDriver ?? const MethodChannelPrivacyScreenDriver();
    _isEnabled = false;
  }

  bool get isSupportedPlatform => _driver.isSupportedPlatform;

  bool get isPrivacyScreenEnabled => _isEnabled;

  Future<bool> setPrivacyScreenEnabled(bool enabled) async {
    if (!_driver.isSupportedPlatform) {
      _isEnabled = false;
      return false;
    }
    final applied = await _driver.setPrivacyScreenEnabled(enabled);
    if (applied) {
      _isEnabled = enabled;
    }
    return applied;
  }
}
