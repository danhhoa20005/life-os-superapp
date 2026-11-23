import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hardware-backed Android Keystore (AES-256-GCM) Secret Vault Bridge.
/// Ensures sensitive credentials (such as SePay API tokens) are stored only inside
/// hardware-protected local storage on Android and NEVER written to Cloud Firestore.
class NativeSecureVaultBridge {
  static const MethodChannel _channel = MethodChannel(
    'vn.lifeos.app/secure_vault',
  );

  static final NativeSecureVaultBridge instance = NativeSecureVaultBridge._();

  final Map<String, String> _memoryFallback = <String, String>{};

  NativeSecureVaultBridge._();

  @visibleForTesting
  NativeSecureVaultBridge.testable();

  bool get _useNativeAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> writeSecret({required String key, required String value}) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await deleteSecret(key);
      return;
    }
    _memoryFallback[key] = trimmed;
    if (_useNativeAndroid) {
      try {
        await _channel.invokeMethod<bool>('writeSecret', <String, dynamic>{
          'key': key,
          'value': trimmed,
        });
      } on MissingPluginException {
        // Running inside unit/widget test harness without Android Activity
      }
    }
  }

  Future<String?> readSecret(String key) async {
    if (_useNativeAndroid) {
      try {
        final res = await _channel.invokeMethod<String>(
          'readSecret',
          <String, dynamic>{'key': key},
        );
        if (res != null && res.isNotEmpty) {
          _memoryFallback[key] = res;
          return res;
        }
      } on MissingPluginException {
        // Fallback to in-memory test store
      }
    }
    return _memoryFallback[key];
  }

  Future<void> deleteSecret(String key) async {
    _memoryFallback.remove(key);
    if (_useNativeAndroid) {
      try {
        await _channel.invokeMethod<bool>('deleteSecret', <String, dynamic>{
          'key': key,
        });
      } on MissingPluginException {
        // Ignore in test harness
      }
    }
  }

  Future<void> clearAllSecrets() async {
    _memoryFallback.clear();
    if (_useNativeAndroid) {
      try {
        await _channel.invokeMethod<bool>('clearAllSecrets');
      } on MissingPluginException {
        // Ignore in test harness
      }
    }
  }

  Future<String?> getVaultDirectoryPath() async {
    if (_useNativeAndroid) {
      try {
        return await _channel.invokeMethod<String>('getVaultDirectoryPath');
      } on MissingPluginException {
        return null;
      }
    }
    return null;
  }
}
