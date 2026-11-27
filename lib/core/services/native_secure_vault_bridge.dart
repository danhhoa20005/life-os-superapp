import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Exception thrown when encrypted vault material fails AEAD authentication,
/// envelope header validation, or SHA-256 integrity verification (fail-closed).
class VaultSecurityException extends FormatException {
  const VaultSecurityException(super.message);

  @override
  String toString() => 'VaultSecurityException: $message';
}

/// Status of reading a secret from [NativeSecureVaultBridge], allowing callers
/// to distinguish key invalidation (`KEY_INVALIDATED`) or native platform failure
/// from a normal missing key.
enum VaultReadStatus { found, missing, keyInvalidated, platformError }

/// Structured outcome of a fail-closed secret read.
final class VaultReadOutcome {
  final String? value;
  final VaultReadStatus status;
  final String? errorCode;

  const VaultReadOutcome({
    required this.value,
    required this.status,
    this.errorCode,
  });

  bool get isKeyInvalidated => status == VaultReadStatus.keyInvalidated;
}

/// Hardware-backed Android Keystore (AES-256-GCM) Secret & Document Vault Bridge.
/// Ensures sensitive credentials (such as SePay API tokens) and private document
/// attachments are protected locally on device and NEVER written in plaintext to
/// disk or Cloud Firestore.
///
/// NOTE: On non-Android platforms (unit/widget test VMs, desktop, Web),
/// [_memoryFallback] is STRICTLY ephemeral / test-only RAM storage and does NOT
/// provide persistent hardware-backed storage. On Android runtime, reads are
/// fail-closed: if native Keystore returns `null` or `KEY_INVALIDATED`, any
/// stale RAM cache entry is purged and `null` is returned.
class NativeSecureVaultBridge {
  static const MethodChannel _channel = MethodChannel(
    'vn.lifeos.app/secure_vault',
  );

  /// 4-byte magic header `"LOSV"` + ver=1 (1B) + ivLen=12 (1B).
  static const List<int> magicHeaderBytes = <int>[0x4C, 0x4F, 0x53, 0x56];
  static const int packetVersion = 1;
  static const int ivLengthBytes = 12;
  static const int _dartTagLengthBytes = 32; // HMAC-SHA256
  static const String _dartAeadMasterKeySlot = '__losv_dart_aead_master_v1__';

  static final NativeSecureVaultBridge instance = NativeSecureVaultBridge._();

  /// Ephemeral/test-only RAM store for non-Android host VMs and test harnesses.
  /// Never trusted as fallback when native Android returns `null` or key invalidation.
  final Map<String, String> _memoryFallback = <String, String>{};
  final Random _secureRandom = Random.secure();
  final bool? _forceNativeAndroidOverride;

  bool _lastReadWasKeyInvalidated = false;
  String? _lastPlatformErrorCode;

  NativeSecureVaultBridge._() : _forceNativeAndroidOverride = null;

  @visibleForTesting
  NativeSecureVaultBridge.testable({bool? forceNativeAndroidOverride})
    : _forceNativeAndroidOverride = forceNativeAndroidOverride;

  /// Whether persistent hardware-backed Android Keystore storage is active on
  /// this runtime platform.
  bool get isPersistentHardwareStorageSupported =>
      !kIsWeb && Platform.isAndroid;

  bool get _useNativeAndroid =>
      _forceNativeAndroidOverride ?? isPersistentHardwareStorageSupported;

  /// True when the most recent [readSecret] / [readSecretOutcome] observed a
  /// native Keystore key invalidation (`KEY_INVALIDATED` / `UnrecoverableKey`).
  bool get lastReadWasKeyInvalidated => _lastReadWasKeyInvalidated;

  String? get lastPlatformErrorCode => _lastPlatformErrorCode;

  @visibleForTesting
  bool debugHasMemoryCacheEntry(String key) => _memoryFallback.containsKey(key);

  @visibleForTesting
  void debugSeedMemoryFallback(String key, String value) {
    _memoryFallback[key] = value;
  }

  static bool _isKeyInvalidatedCode(String code, String? message) {
    final upperCode = code.trim().toUpperCase();
    if (upperCode == 'KEY_INVALIDATED' ||
        upperCode == 'KEY_PERMANENTLY_INVALIDATED' ||
        upperCode == 'VAULT_KEY_INVALIDATED' ||
        upperCode == 'UNRECOVERABLE_KEY') {
      return true;
    }
    final upperMsg = (message ?? '').toUpperCase();
    return upperMsg.contains('KEY_INVALIDATED') ||
        upperMsg.contains('KEYPERMANENTLYINVALIDATED') ||
        upperMsg.contains('UNRECOVERABLEKEY');
  }

  Future<void> writeSecret({required String key, required String value}) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await deleteSecret(key);
      return;
    }
    if (_useNativeAndroid) {
      try {
        await _channel.invokeMethod<bool>('writeSecret', <String, dynamic>{
          'key': key,
          'value': trimmed,
        });
        _memoryFallback[key] = trimmed;
      } on MissingPluginException {
        // Running inside unit/widget test harness without Android Activity
        _memoryFallback[key] = trimmed;
      } on PlatformException catch (e) {
        _memoryFallback.remove(key);
        throw VaultSecurityException(
          'Native hardware vault write failed (${e.code}): ${e.message ?? e.code}',
        );
      }
      return;
    }
    _memoryFallback[key] = trimmed;
  }

  Future<VaultReadOutcome> readSecretOutcome(String key) async {
    _lastReadWasKeyInvalidated = false;
    _lastPlatformErrorCode = null;
    if (_useNativeAndroid) {
      try {
        final res = await _channel.invokeMethod<String>(
          'readSecret',
          <String, dynamic>{'key': key},
        );
        if (res != null && res.isNotEmpty) {
          _memoryFallback[key] = res;
          return VaultReadOutcome(value: res, status: VaultReadStatus.found);
        }
        // Fail-closed: NEVER fall back to stale RAM cache when native Android
        // returns null/empty (missing or invalidated key)!
        _memoryFallback.remove(key);
        return const VaultReadOutcome(
          value: null,
          status: VaultReadStatus.missing,
        );
      } on PlatformException catch (e) {
        // Fail-closed: purge any stale RAM entry and surface invalidation status.
        _memoryFallback.remove(key);
        _lastPlatformErrorCode = e.code;
        final invalidated = _isKeyInvalidatedCode(e.code, e.message);
        _lastReadWasKeyInvalidated = invalidated;
        return VaultReadOutcome(
          value: null,
          status: invalidated
              ? VaultReadStatus.keyInvalidated
              : VaultReadStatus.platformError,
          errorCode: e.code,
        );
      } on MissingPluginException {
        // Fallback to ephemeral in-memory test store ONLY in unbridged test harness
      }
    }
    final mem = _memoryFallback[key];
    return VaultReadOutcome(
      value: mem,
      status: (mem != null && mem.isNotEmpty)
          ? VaultReadStatus.found
          : VaultReadStatus.missing,
    );
  }

  Future<String?> readSecret(String key) async {
    final outcome = await readSecretOutcome(key);
    return outcome.value;
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

  /// Clears ephemeral RAM cache on sign-out / session reset so stale user secrets
  /// never persist in memory across accounts.
  void clearMemoryFallbackOnSessionReset({bool includeAeadMasterKey = false}) {
    _lastReadWasKeyInvalidated = false;
    _lastPlatformErrorCode = null;
    if (_useNativeAndroid || includeAeadMasterKey) {
      _memoryFallback.clear();
      return;
    }
    _memoryFallback.removeWhere((key, _) => key != _dartAeadMasterKeySlot);
  }

  Future<void> clearAllSecrets() async {
    _memoryFallback.clear();
    _lastReadWasKeyInvalidated = false;
    _lastPlatformErrorCode = null;
    if (_useNativeAndroid) {
      try {
        await _channel.invokeMethod<bool>('clearAllSecrets');
      } on MissingPluginException {
        // Ignore in test harness
      }
    }
  }

  static String? _sanitizeUidOrNull(String? userId) {
    final trimmed = (userId ?? '').trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') return null;
    final sanitized = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') return null;
    return sanitized;
  }

  /// Returns true iff [key] is explicitly scoped to [userId] (or its sanitized
  /// segment), ensuring other users' secrets & global AEAD keys stay intact.
  @visibleForTesting
  static bool isKeyScopedToUser(String key, String userId) {
    final trimmed = userId.trim();
    final safeUid = _sanitizeUidOrNull(trimmed);
    if (safeUid == null ||
        key.trim().isEmpty ||
        key == _dartAeadMasterKeySlot) {
      return false;
    }
    final candidates = <String>{trimmed, safeUid};

    if (key.contains('__u_')) {
      final afterMarker = key.split('__u_').skip(1).join('__u_');
      return candidates.any(
        (uid) =>
            afterMarker == uid ||
            afterMarker.startsWith('${uid}__') ||
            afterMarker.startsWith('$uid:'),
      );
    }

    return candidates.any(
      (uid) =>
          key.startsWith('${uid}_') ||
          key.endsWith('_$uid') ||
          key.contains(':$uid:') ||
          key.startsWith('$uid:') ||
          key.endsWith(':$uid'),
    );
  }

  /// Account-scoped secret purge (H4 + VAULT-03): deletes ONLY secrets belonging
  /// to [userId] (never calling `clearAllSecrets` or touching another user's credentials).
  /// Returns `true` when all target user secrets/directories/export caches were
  /// verified removed, or `false` if native cleanup failed or [userId] is invalid.
  Future<bool> clearSecretsForUser(String userId) async {
    final cleanUid = userId.trim();
    if (_sanitizeUidOrNull(cleanUid) == null) return false;

    final keysToRemove = _memoryFallback.keys
        .where(
          (k) => k != _dartAeadMasterKeySlot && isKeyScopedToUser(k, cleanUid),
        )
        .toList();
    for (final key in keysToRemove) {
      _memoryFallback.remove(key);
    }

    if (_useNativeAndroid) {
      try {
        final cleared = await _channel.invokeMethod<bool>(
          'clearUserSecrets',
          <String, dynamic>{'userId': cleanUid},
        );
        return cleared ?? false;
      } on MissingPluginException {
        // Ignore in test harness
        return true;
      } on PlatformException {
        return false;
      }
    }
    return true;
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

  /// Optional legacy `filesDir/secure_doc_vault` fallback path for reading
  /// attachments created before migration to `noBackupFilesDir`.
  Future<String?> getLegacyVaultDirectoryPath() async {
    if (_useNativeAndroid) {
      try {
        return await _channel.invokeMethod<String>(
          'getLegacyVaultDirectoryPath',
        );
      } on MissingPluginException {
        return null;
      }
    }
    return null;
  }

  /// Encrypts [plainBytes] using Android Keystore AES-256-GCM (`LifeOsSecureVault`)
  /// on Android, or pure-Dart 256-bit CTR + HMAC-SHA256 AEAD in VM/non-Android
  /// environments. Envelope format: `"LOSV"(4B) + ver=1(1B) + ivLen=12(1B) + iv(12B) + payloadWithTag`.
  Future<Uint8List> encryptBytes({
    required Uint8List plainBytes,
    String aad = '',
  }) async {
    if (_useNativeAndroid) {
      try {
        final encrypted = await _channel.invokeMethod<Uint8List>(
          'encryptBytes',
          <String, dynamic>{'plainBytes': plainBytes, 'aad': aad},
        );
        if (encrypted != null && encrypted.isNotEmpty) {
          return encrypted;
        }
      } on MissingPluginException {
        // Fallback to pure-Dart AEAD in test harness or unbridged host
      } on PlatformException catch (e) {
        throw VaultSecurityException(
          'Native hardware vault encryption failed: ${e.message ?? e.code}',
        );
      }
    }
    return _encryptDartAead(plainBytes, aad: aad);
  }

  /// Decrypts and authenticates [cipherPack] bound to [aad]. Fails closed with
  /// [VaultSecurityException] (`is FormatException`) on any tag/AAD/header mismatch.
  Future<Uint8List> decryptBytes({
    required Uint8List cipherPack,
    String aad = '',
  }) async {
    if (_useNativeAndroid) {
      try {
        final decrypted = await _channel.invokeMethod<Uint8List>(
          'decryptBytes',
          <String, dynamic>{'cipherPack': cipherPack, 'aad': aad},
        );
        if (decrypted != null) {
          return decrypted;
        }
      } on MissingPluginException {
        // Fallback to pure-Dart AEAD in test harness or unbridged host
      } on PlatformException catch (e) {
        throw VaultSecurityException(
          'Native hardware vault decryption rejected payload: ${e.message ?? e.code}',
        );
      }
    }
    return _decryptDartAead(cipherPack, aad: aad);
  }

  Uint8List _getOrCreateDartMasterKey() {
    final existingB64 = _memoryFallback[_dartAeadMasterKeySlot];
    if (existingB64 != null && existingB64.isNotEmpty) {
      final decoded = base64Decode(existingB64);
      if (decoded.length == 32) {
        return decoded;
      }
    }
    final key = Uint8List(32);
    for (var i = 0; i < key.length; i++) {
      key[i] = _secureRandom.nextInt(256);
    }
    _memoryFallback[_dartAeadMasterKeySlot] = base64Encode(key);
    return key;
  }

  ({List<int> encKey, List<int> macKey}) _deriveSubkeys(Uint8List masterKey) {
    final encKey = Hmac(
      sha256,
      masterKey,
    ).convert(utf8.encode('LOSV_ENC_CTR_V1')).bytes;
    final macKey = Hmac(
      sha256,
      masterKey,
    ).convert(utf8.encode('LOSV_AUTH_MAC_V1')).bytes;
    return (encKey: encKey, macKey: macKey);
  }

  Uint8List _xorCtrKeystream({
    required List<int> encKey,
    required Uint8List iv,
    required Uint8List input,
  }) {
    final output = Uint8List(input.length);
    final hmac = Hmac(sha256, encKey);
    final blockInput = Uint8List(iv.length + 4)..setRange(0, iv.length, iv);
    var offset = 0;
    var counter = 0;
    while (offset < input.length) {
      blockInput[iv.length] = (counter >> 24) & 0xFF;
      blockInput[iv.length + 1] = (counter >> 16) & 0xFF;
      blockInput[iv.length + 2] = (counter >> 8) & 0xFF;
      blockInput[iv.length + 3] = counter & 0xFF;
      final keystream = hmac.convert(blockInput).bytes;
      final chunkLen = min(32, input.length - offset);
      for (var i = 0; i < chunkLen; i++) {
        output[offset + i] = input[offset + i] ^ keystream[i];
      }
      offset += chunkLen;
      counter += 1;
    }
    return output;
  }

  List<int> _computeAuthTag({
    required List<int> macKey,
    required Uint8List headerAndIv,
    required Uint8List ciphertext,
    required String aad,
  }) {
    final aadBytes = utf8.encode(aad);
    final authBuffer = Uint8List(
      headerAndIv.length + 4 + aadBytes.length + ciphertext.length,
    );
    var cursor = 0;
    authBuffer.setRange(cursor, cursor + headerAndIv.length, headerAndIv);
    cursor += headerAndIv.length;
    authBuffer[cursor++] = (aadBytes.length >> 24) & 0xFF;
    authBuffer[cursor++] = (aadBytes.length >> 16) & 0xFF;
    authBuffer[cursor++] = (aadBytes.length >> 8) & 0xFF;
    authBuffer[cursor++] = aadBytes.length & 0xFF;
    if (aadBytes.isNotEmpty) {
      authBuffer.setRange(cursor, cursor + aadBytes.length, aadBytes);
      cursor += aadBytes.length;
    }
    if (ciphertext.isNotEmpty) {
      authBuffer.setRange(cursor, cursor + ciphertext.length, ciphertext);
    }
    return Hmac(sha256, macKey).convert(authBuffer).bytes;
  }

  Uint8List _encryptDartAead(Uint8List plainBytes, {String aad = ''}) {
    final masterKey = _getOrCreateDartMasterKey();
    final subkeys = _deriveSubkeys(masterKey);
    final iv = Uint8List(ivLengthBytes);
    for (var i = 0; i < iv.length; i++) {
      iv[i] = _secureRandom.nextInt(256);
    }

    final headerLen = 6;
    final headerAndIv = Uint8List(headerLen + ivLengthBytes)
      ..setRange(0, 4, magicHeaderBytes)
      ..[4] = packetVersion
      ..[5] = ivLengthBytes
      ..setRange(6, 6 + ivLengthBytes, iv);

    final ciphertext = _xorCtrKeystream(
      encKey: subkeys.encKey,
      iv: iv,
      input: plainBytes,
    );
    final tag = _computeAuthTag(
      macKey: subkeys.macKey,
      headerAndIv: headerAndIv,
      ciphertext: ciphertext,
      aad: aad,
    );

    final packet = Uint8List(
      headerAndIv.length + ciphertext.length + _dartTagLengthBytes,
    );
    packet.setRange(0, headerAndIv.length, headerAndIv);
    if (ciphertext.isNotEmpty) {
      packet.setRange(
        headerAndIv.length,
        headerAndIv.length + ciphertext.length,
        ciphertext,
      );
    }
    packet.setRange(headerAndIv.length + ciphertext.length, packet.length, tag);
    return packet;
  }

  Uint8List _decryptDartAead(Uint8List cipherPack, {String aad = ''}) {
    const minLen = 6 + ivLengthBytes + _dartTagLengthBytes;
    if (cipherPack.length < minLen) {
      throw VaultSecurityException(
        'Invalid vault packet length (${cipherPack.length} bytes).',
      );
    }
    for (var i = 0; i < magicHeaderBytes.length; i++) {
      if (cipherPack[i] != magicHeaderBytes[i]) {
        throw const VaultSecurityException(
          'Vault payload missing valid LOSV magic header.',
        );
      }
    }
    if (cipherPack[4] != packetVersion) {
      throw VaultSecurityException(
        'Unsupported vault packet version: ${cipherPack[4]}.',
      );
    }
    final ivLen = cipherPack[5];
    if (ivLen != ivLengthBytes ||
        cipherPack.length < 6 + ivLen + _dartTagLengthBytes) {
      throw VaultSecurityException('Invalid vault IV length: $ivLen.');
    }

    final headerAndIvLen = 6 + ivLen;
    final headerAndIv = Uint8List.sublistView(cipherPack, 0, headerAndIvLen);
    final iv = Uint8List.sublistView(cipherPack, 6, headerAndIvLen);
    final ctEnd = cipherPack.length - _dartTagLengthBytes;
    final ciphertext = Uint8List.sublistView(cipherPack, headerAndIvLen, ctEnd);
    final actualTag = Uint8List.sublistView(cipherPack, ctEnd);

    final masterKey = _getOrCreateDartMasterKey();
    final subkeys = _deriveSubkeys(masterKey);
    final expectedTag = _computeAuthTag(
      macKey: subkeys.macKey,
      headerAndIv: headerAndIv,
      ciphertext: ciphertext,
      aad: aad,
    );

    var diff = 0;
    for (var i = 0; i < _dartTagLengthBytes; i++) {
      diff |= expectedTag[i] ^ actualTag[i];
    }
    if (diff != 0) {
      throw const VaultSecurityException(
        'AEAD authentication tag verification failed (tampered or wrong AAD/key).',
      );
    }

    return _xorCtrKeystream(encKey: subkeys.encKey, iv: iv, input: ciphertext);
  }
}
