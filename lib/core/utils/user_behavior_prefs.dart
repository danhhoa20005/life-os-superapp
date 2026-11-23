import '../services/native_secure_vault_bridge.dart';
import 'vnd_amount.dart';

/// Persists everyday user habits & preferences (last-used wallet, privacy balance mask,
/// pinned home shortcuts) and provides Vietnamese shorthand entry helpers.
abstract final class UserBehaviorPrefs {
  static const String _keyLastWallet = 'ux_last_used_wallet_id';
  static const String _keyPinnedShortcuts = 'ux_home_pinned_shortcuts_v1';
  static const String _keyHideBalances = 'ux_privacy_hide_balances';

  static String? _cachedLastWalletId;
  static bool? _cachedHideBalances;

  static Future<void> resetForTest() async {
    _cachedLastWalletId = null;
    _cachedHideBalances = null;
    await NativeSecureVaultBridge.instance.deleteSecret(_keyLastWallet);
    await NativeSecureVaultBridge.instance.deleteSecret(_keyPinnedShortcuts);
    await NativeSecureVaultBridge.instance.deleteSecret(_keyHideBalances);
  }

  static Future<void> rememberWallet(String walletId) async {
    if (walletId.trim().isEmpty) return;
    _cachedLastWalletId = walletId.trim();
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _keyLastWallet,
      value: _cachedLastWalletId!,
    );
  }

  static String? get cachedLastWalletId => _cachedLastWalletId;

  static Future<String?> loadLastWalletId() async {
    final v = await NativeSecureVaultBridge.instance.readSecret(_keyLastWallet);
    if (v != null && v.isNotEmpty) {
      _cachedLastWalletId = v;
    }
    return _cachedLastWalletId;
  }

  static String resolvePreferredWalletId(
    Iterable<String> availableWalletIds, {
    String fallback = 'wallet_cash_default',
  }) {
    final list = availableWalletIds.toList();
    if (list.isEmpty) return fallback;
    if (_cachedLastWalletId != null && list.contains(_cachedLastWalletId)) {
      return _cachedLastWalletId!;
    }
    return list.first;
  }

  static Future<void> savePinnedShortcuts(Set<String> ids) async {
    if (ids.isEmpty) return;
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _keyPinnedShortcuts,
      value: ids.join(','),
    );
  }

  static Future<List<String>?> loadPinnedShortcuts() async {
    final raw = await NativeSecureVaultBridge.instance.readSecret(_keyPinnedShortcuts);
    if (raw == null || raw.trim().isEmpty) return null;
    final items = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return items.length >= 4 ? items : null;
  }

  static Future<void> saveHideBalances(bool hide) async {
    _cachedHideBalances = hide;
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _keyHideBalances,
      value: hide ? '1' : '0',
    );
  }

  static Future<bool> loadHideBalances() async {
    final raw = await NativeSecureVaultBridge.instance.readSecret(_keyHideBalances);
    if (raw != null) {
      _cachedHideBalances = raw == '1';
    }
    return _cachedHideBalances ?? false;
  }

  /// Generates instant `.000` / `.0000` / `.000.000` Vietnamese VND completions when a user
  /// types short digits (e.g. `"45"` -> `[45.000, 450.000, 4.500.000]`).
  static List<(int amountMinor, String label)> vndZeroPadSuggestions(String rawInput) {
    final digitsOnly = rawInput.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return const [];
    final base = int.tryParse(digitsOnly);
    if (base == null || base <= 0 || base >= 10000) return const [];

    final candidates = <int>[
      base * 1000,
      base * 10000,
      base * 100000,
      if (base < 100) base * 1000000,
    ];

    final results = <(int, String)>[];
    for (final val in candidates) {
      if (val >= 1000 && val <= 500000000) {
        results.add((val, VndAmount.format(val)));
      }
      if (results.length >= 3) break;
    }
    return results;
  }

  /// Contextual Vietnamese time-of-day greeting phrase matching real daily rhythm.
  static String contextualTimeSubtitle(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 11) return 'Chào buổi sáng';
    if (h >= 11 && h < 14) return 'Giờ nghỉ trưa';
    if (h >= 14 && h < 18) return 'Chào buổi chiều';
    return 'Buổi tối thư thái';
  }
}
