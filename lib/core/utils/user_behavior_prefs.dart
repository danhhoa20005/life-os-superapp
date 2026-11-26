import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../behavior/behavior_domain.dart';
import '../behavior/behavior_engine.dart';
import '../behavior/local_behavior_store.dart';
import '../services/native_secure_vault_bridge.dart';
import 'vnd_amount.dart';

export '../behavior/behavior_domain.dart' show HabitShortcut;

/// Persists everyday user habits & preferences (last-used wallet, privacy balance mask,
/// pinned home shortcuts, RFM habit memory, personalization settings) and provides
/// Vietnamese shorthand & circadian helpers.
abstract final class UserBehaviorPrefs {
  static const String _keyLastWallet = 'ux_last_used_wallet_id';
  static const String _keyPinnedShortcuts = 'ux_home_pinned_shortcuts_v1';
  static const String _keyHideBalances = 'ux_privacy_hide_balances';
  static const String _keyHabitActions = 'ux_habit_actions_rfm_v1';
  static const String _keySecurityPin = 'sec_app_pin_code_v1';
  static const String _keyPermissionsPopupDismissed =
      'ux_permissions_popup_dismissed_v1';
  static const String _keyPreferredVoiceEngineMode =
      'ux_preferred_voice_engine_mode_v2';
  static const String _keyUserInterests = 'ux_user_interests_v1';
  static const String _keyOnboardingSkipped = 'ux_onboarding_skipped_v1';
  static const String _keyPersonalizationEnabled =
      'ux_personalization_enabled_v1';
  static const String _keyFirstActionTipDismissed =
      'ux_first_action_tip_dismissed_v1';
  static const String _keyRecentSearches = 'ux_recent_searches_v1';

  static String? _activeUserId;
  static String? _cachedLastWalletId;
  static bool? _cachedHideBalances;
  static String? _cachedAppPin;
  static bool? _cachedPermissionsPopupDismissed;
  static String? _cachedVoiceEngineMode;
  static Set<String>? _cachedUserInterests;
  static bool? _cachedOnboardingSkipped;
  static bool? _cachedPersonalizationEnabled;
  static bool? _cachedFirstActionTipDismissed;
  static List<String>? _cachedRecentSearches;
  static bool _habitsLoadedForActiveUser = false;
  static List<HabitShortcut> _cachedHabits = const <HabitShortcut>[];
  static final Set<String> _trackedScopedKeys = <String>{};

  static String? get activeUserId => _activeUserId;

  static String _scopedKey(String baseKey) {
    final uid = _activeUserId;
    final key = (uid == null || uid.isEmpty) ? baseKey : '${baseKey}__u_$uid';
    _trackedScopedKeys.add(key);
    return key;
  }

  static void _clearInMemoryCaches() {
    _cachedLastWalletId = null;
    _cachedHideBalances = null;
    _cachedAppPin = null;
    _cachedPermissionsPopupDismissed = null;
    _cachedVoiceEngineMode = null;
    _cachedUserInterests = null;
    _cachedOnboardingSkipped = null;
    _cachedPersonalizationEnabled = null;
    _cachedFirstActionTipDismissed = null;
    _cachedRecentSearches = null;
    _habitsLoadedForActiveUser = false;
    _cachedHabits = const <HabitShortcut>[];
  }

  /// Binds local user-preference storage to [userId] so wallets, privacy masks,
  /// PIN codes, voice mode, permissions prompt, and RFM habit chips never leak
  /// across accounts on a shared device.
  static void bindActiveUser(String? userId) {
    final cleaned = (userId ?? '').trim();
    final nextId = cleaned.isEmpty ? null : cleaned;
    if (_activeUserId == nextId) return;
    _activeUserId = nextId;
    _clearInMemoryCaches();
    LocalBehaviorStore.instance.bindActiveUser(nextId);
  }

  /// Clears in-memory session caches immediately when the active user signs out.
  static void clearSessionOnSignOut() {
    _activeUserId = null;
    _clearInMemoryCaches();
    LocalBehaviorStore.instance.clearSessionOnSignOut();
  }

  /// Clears ONLY in-memory caches and active user binding to simulate a cold
  /// app restart in tests while preserving persisted storage.
  @visibleForTesting
  static void simulateAppRestartForTest() {
    _activeUserId = null;
    _clearInMemoryCaches();
    LocalBehaviorStore.instance.clearSessionOnSignOut();
  }

  static Future<void> resetForTest() async {
    _activeUserId = null;
    _clearInMemoryCaches();
    await LocalBehaviorStore.instance.resetForTest();
    for (final k in _trackedScopedKeys.toList()) {
      await NativeSecureVaultBridge.instance.deleteSecret(k);
    }
    _trackedScopedKeys.clear();
    await NativeSecureVaultBridge.instance.deleteSecret(_keyLastWallet);
    await NativeSecureVaultBridge.instance.deleteSecret(_keyPinnedShortcuts);
    await NativeSecureVaultBridge.instance.deleteSecret(_keyHideBalances);
    await NativeSecureVaultBridge.instance.deleteSecret(_keyHabitActions);
    await NativeSecureVaultBridge.instance.deleteSecret(_keySecurityPin);
    await NativeSecureVaultBridge.instance.deleteSecret(
      _keyPermissionsPopupDismissed,
    );
    await NativeSecureVaultBridge.instance.deleteSecret(
      _keyPreferredVoiceEngineMode,
    );
    await NativeSecureVaultBridge.instance.deleteSecret(_keyUserInterests);
    await NativeSecureVaultBridge.instance.deleteSecret(_keyOnboardingSkipped);
    await NativeSecureVaultBridge.instance.deleteSecret(
      _keyPersonalizationEnabled,
    );
    await NativeSecureVaultBridge.instance.deleteSecret(
      _keyFirstActionTipDismissed,
    );
    await NativeSecureVaultBridge.instance.deleteSecret(_keyRecentSearches);
  }

  static String normalizeVoiceEngineMode(String? raw) {
    final norm = (raw ?? '').trim().toLowerCase();
    return switch (norm) {
      'offline_strict' || 'on_device' => 'offline_strict',
      'system_dialog' || 'system_speech_dialog' => 'system_dialog',
      'hybrid_auto' || 'auto' => 'hybrid_auto',
      'online_google' => 'online_google',
      'google_service' => 'google_service',
      _ => 'google_service',
    };
  }

  static String get cachedVoiceEngineMode =>
      _cachedVoiceEngineMode ?? 'google_service';

  static Future<String> loadPreferredVoiceEngineMode() async {
    if (_cachedVoiceEngineMode != null) return _cachedVoiceEngineMode!;
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _scopedKey(_keyPreferredVoiceEngineMode),
    );
    _cachedVoiceEngineMode = normalizeVoiceEngineMode(raw);
    return _cachedVoiceEngineMode!;
  }

  static Future<void> savePreferredVoiceEngineMode(String modeWireValue) async {
    final normalized = normalizeVoiceEngineMode(modeWireValue);
    _cachedVoiceEngineMode = normalized;
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _scopedKey(_keyPreferredVoiceEngineMode),
      value: normalized,
    );
  }

  static Future<bool> hasDismissedPermissionsPopup() async {
    if (_cachedPermissionsPopupDismissed != null) {
      return _cachedPermissionsPopupDismissed!;
    }
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _scopedKey(_keyPermissionsPopupDismissed),
    );
    _cachedPermissionsPopupDismissed = raw == '1';
    return _cachedPermissionsPopupDismissed!;
  }

  static Future<void> markPermissionsPopupDismissed([
    bool dismissed = true,
  ]) async {
    _cachedPermissionsPopupDismissed = dismissed;
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _scopedKey(_keyPermissionsPopupDismissed),
      value: dismissed ? '1' : '0',
    );
  }

  static Future<void> saveAppPinCode(String? pin) async {
    final cleaned = (pin ?? '').trim();
    final key = _scopedKey(_keySecurityPin);
    if (cleaned.isEmpty) {
      _cachedAppPin = null;
      await NativeSecureVaultBridge.instance.deleteSecret(key);
      return;
    }
    _cachedAppPin = cleaned;
    await NativeSecureVaultBridge.instance.writeSecret(
      key: key,
      value: cleaned,
    );
  }

  static Future<String?> loadAppPinCode() async {
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _scopedKey(_keySecurityPin),
    );
    if (raw != null && raw.trim().isNotEmpty) {
      _cachedAppPin = raw.trim();
    } else {
      _cachedAppPin = null;
    }
    return _cachedAppPin;
  }

  static Future<bool> hasAppPinCode() async {
    final pin = await loadAppPinCode();
    return pin != null && pin.length >= 4;
  }

  static Future<bool> verifyAppPinCode(String candidate) async {
    final stored = await loadAppPinCode();
    final input = candidate.trim();
    if (stored == null || stored.length != input.length) return false;
    var diff = 0;
    for (var i = 0; i < stored.length; i++) {
      diff |= stored.codeUnitAt(i) ^ input.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Future<void> rememberWallet(String walletId) async {
    if (walletId.trim().isEmpty) return;
    _cachedLastWalletId = walletId.trim();
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _scopedKey(_keyLastWallet),
      value: _cachedLastWalletId!,
    );
  }

  static String? get cachedLastWalletId => _cachedLastWalletId;

  static Future<String?> loadLastWalletId() async {
    final v = await NativeSecureVaultBridge.instance.readSecret(
      _scopedKey(_keyLastWallet),
    );
    if (v != null && v.isNotEmpty) {
      _cachedLastWalletId = v;
    } else {
      _cachedLastWalletId = null;
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
      key: _scopedKey(_keyPinnedShortcuts),
      value: ids.join(','),
    );
  }

  static Future<List<String>?> loadPinnedShortcuts() async {
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _scopedKey(_keyPinnedShortcuts),
    );
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
      key: _scopedKey(_keyHideBalances),
      value: hide ? '1' : '0',
    );
  }

  static Future<bool> loadHideBalances() async {
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _scopedKey(_keyHideBalances),
    );
    if (raw != null) {
      _cachedHideBalances = raw == '1';
    } else {
      _cachedHideBalances = false;
    }
    return _cachedHideBalances ?? false;
  }

  /// Loads persisted RFM habit shortcuts from hardware-backed local storage.
  static Future<List<HabitShortcut>> loadHabitShortcuts() async {
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _scopedKey(_keyHabitActions),
    );
    _habitsLoadedForActiveUser = true;
    if (raw == null || raw.trim().isEmpty) {
      _cachedHabits = const <HabitShortcut>[];
      return _cachedHabits;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _cachedHabits = decoded
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => HabitShortcut.fromJson(Map<String, dynamic>.from(m)))
            .where((h) => h.id.isNotEmpty && h.commandText.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {
      // Ignore malformed local cache safely
    }
    return _cachedHabits;
  }

  /// Records a completed quick action into RFM habit memory (max 16 habits),
  /// hydrating existing habits first, merging amount-free canonical IDs, and
  /// computing midnight-safe circular-mean typical hours.
  static Future<void> recordHabitExecution({
    required String label,
    required String commandText,
    String categoryName = '',
    int amountMinor = 0,
    DateTime? now,
  }) async {
    final cleanCmd = commandText.trim();
    final cleanLabel = label.trim();
    if (cleanCmd.isEmpty || cleanLabel.isEmpty) return;

    if (!_habitsLoadedForActiveUser) {
      await loadHabitShortcuts();
    }

    final refNow = now ?? DateTime.now();
    _cachedHabits = RecencyFrequencyEngine.upsertHabitShortcut(
      existing: _cachedHabits,
      label: cleanLabel,
      commandText: cleanCmd,
      categoryName: categoryName,
      amountMinor: amountMinor,
      now: refNow,
      maxItems: 16,
    );

    await NativeSecureVaultBridge.instance.writeSecret(
      key: _scopedKey(_keyHabitActions),
      value: jsonEncode(_cachedHabits.map((h) => h.toJson()).toList()),
    );

    final canonicalId = RecencyFrequencyEngine.canonicalizeHabitId(cleanLabel);
    await BehaviorEventCollector().recordType(
      BehaviorEventType.quickActionUsed,
      timestamp: refNow,
      metadata: <String, Object?>{
        'targetId': canonicalId,
        'hourOfDay': refNow.hour,
        'weekday': refNow.weekday,
      },
    );
  }

  /// Loads account-scoped interest group IDs (`ux_user_interests_v1`).
  static Future<Set<String>> loadUserInterests() async {
    if (_cachedUserInterests != null) return _cachedUserInterests!;
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _scopedKey(_keyUserInterests),
    );
    if (raw == null || raw.trim().isEmpty) {
      _cachedUserInterests = const <String>{};
      return _cachedUserInterests!;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _cachedUserInterests = Set<String>.unmodifiable(
          decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty),
        );
        return _cachedUserInterests!;
      }
    } catch (_) {
      // Fallback to comma-separated format if needed
    }
    _cachedUserInterests = Set<String>.unmodifiable(
      raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
    );
    return _cachedUserInterests!;
  }

  /// Saves account-scoped interest group IDs (`ux_user_interests_v1`).
  static Future<void> saveUserInterests(Set<String> ids) async {
    final cleaned = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    _cachedUserInterests = Set<String>.unmodifiable(cleaned);
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _scopedKey(_keyUserInterests),
      value: jsonEncode(cleaned.toList()),
    );

    final currentSettings = await LocalBehaviorStore.instance.loadSettings();
    final parsedGroups = UserInterestGroup.fromIds(cleaned);
    await LocalBehaviorStore.instance.saveSettings(
      currentSettings.copyWith(
        selectedInterests: parsedGroups.isEmpty
            ? const <UserInterestGroup>{UserInterestGroup.all}
            : Set<UserInterestGroup>.unmodifiable(parsedGroups),
      ),
    );
  }

  /// Loads whether the active user skipped onboarding (`ux_onboarding_skipped_v1`).
  static Future<bool> loadOnboardingSkipped() async {
    if (_cachedOnboardingSkipped != null) return _cachedOnboardingSkipped!;
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _scopedKey(_keyOnboardingSkipped),
    );
    _cachedOnboardingSkipped = raw == '1';
    return _cachedOnboardingSkipped!;
  }

  /// Saves whether the active user skipped onboarding (`ux_onboarding_skipped_v1`).
  static Future<void> saveOnboardingSkipped(bool skipped) async {
    _cachedOnboardingSkipped = skipped;
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _scopedKey(_keyOnboardingSkipped),
      value: skipped ? '1' : '0',
    );
  }

  /// Loads whether smart adaptive personalization is enabled (`ux_personalization_enabled_v1`).
  static Future<bool> loadPersonalizationEnabled() async {
    if (_cachedPersonalizationEnabled != null) {
      return _cachedPersonalizationEnabled!;
    }
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _scopedKey(_keyPersonalizationEnabled),
    );
    _cachedPersonalizationEnabled = raw != '0';
    return _cachedPersonalizationEnabled!;
  }

  /// Saves whether smart adaptive personalization is enabled (`ux_personalization_enabled_v1`).
  static Future<void> savePersonalizationEnabled(bool enabled) async {
    _cachedPersonalizationEnabled = enabled;
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _scopedKey(_keyPersonalizationEnabled),
      value: enabled ? '1' : '0',
    );

    final currentSettings = await LocalBehaviorStore.instance.loadSettings();
    await LocalBehaviorStore.instance.saveSettings(
      currentSettings.copyWith(enabled: enabled),
    );
  }

  /// Loads whether the FTUE first-action tip card was dismissed (`ux_first_action_tip_dismissed_v1`).
  static Future<bool> loadFirstActionTipDismissed() async {
    if (_cachedFirstActionTipDismissed != null) {
      return _cachedFirstActionTipDismissed!;
    }
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _scopedKey(_keyFirstActionTipDismissed),
    );
    _cachedFirstActionTipDismissed = raw == '1';
    return _cachedFirstActionTipDismissed!;
  }

  /// Saves whether the FTUE first-action tip card was dismissed (`ux_first_action_tip_dismissed_v1`).
  static Future<void> saveFirstActionTipDismissed(bool dismissed) async {
    _cachedFirstActionTipDismissed = dismissed;
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _scopedKey(_keyFirstActionTipDismissed),
      value: dismissed ? '1' : '0',
    );
  }

  /// Loads account-scoped recent search queries (`ux_recent_searches_v1`).
  static Future<List<String>> loadRecentSearches() async {
    if (_cachedRecentSearches != null) return _cachedRecentSearches!;
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _scopedKey(_keyRecentSearches),
    );
    if (raw == null || raw.trim().isEmpty) {
      _cachedRecentSearches = const <String>[];
      return _cachedRecentSearches!;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _cachedRecentSearches = List<String>.unmodifiable(
          decoded
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .take(10),
        );
        return _cachedRecentSearches!;
      }
    } catch (_) {
      // Ignore malformed cache safely
    }
    _cachedRecentSearches = const <String>[];
    return _cachedRecentSearches!;
  }

  /// Persists deduplicated account-scoped recent search queries (`ux_recent_searches_v1`).
  static Future<void> saveRecentSearches(List<String> queries) async {
    final seen = <String>{};
    final cleaned = <String>[];
    for (final raw in queries) {
      final item = raw.trim();
      if (item.isEmpty) continue;
      if (seen.add(item.toLowerCase())) {
        cleaned.add(item);
      }
      if (cleaned.length >= 10) break;
    }
    _cachedRecentSearches = List<String>.unmodifiable(cleaned);
    if (cleaned.isEmpty) {
      await NativeSecureVaultBridge.instance.deleteSecret(
        _scopedKey(_keyRecentSearches),
      );
      return;
    }
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _scopedKey(_keyRecentSearches),
      value: jsonEncode(cleaned),
    );
  }

  /// Clears account-scoped recent search queries (`ux_recent_searches_v1`).
  static Future<void> clearRecentSearches() async {
    _cachedRecentSearches = const <String>[];
    await NativeSecureVaultBridge.instance.deleteSecret(
      _scopedKey(_keyRecentSearches),
    );
  }

  /// Resets ALL behavior, habit, interest, recommendation dismissal, and local UX
  /// metrics data strictly for the active user without touching other accounts.
  static Future<void> resetAllBehaviorDataForActiveUser() async {
    _cachedHabits = const <HabitShortcut>[];
    _habitsLoadedForActiveUser = true;
    _cachedUserInterests = const <String>{};
    _cachedPersonalizationEnabled = true;
    _cachedFirstActionTipDismissed = false;
    _cachedRecentSearches = const <String>[];

    await NativeSecureVaultBridge.instance.deleteSecret(
      _scopedKey(_keyHabitActions),
    );
    await NativeSecureVaultBridge.instance.deleteSecret(
      _scopedKey(_keyUserInterests),
    );
    await NativeSecureVaultBridge.instance.deleteSecret(
      _scopedKey(_keyPersonalizationEnabled),
    );
    await NativeSecureVaultBridge.instance.deleteSecret(
      _scopedKey(_keyFirstActionTipDismissed),
    );
    await NativeSecureVaultBridge.instance.deleteSecret(
      _scopedKey(_keyRecentSearches),
    );
    await LocalBehaviorStore.instance.resetAllForActiveUser();
  }

  /// Returns top habits ranked by RFM + Circadian Time-of-Day score.
  static List<HabitShortcut> topRankedHabits({DateTime? now, int limit = 4}) {
    if (_cachedHabits.isEmpty) return const <HabitShortcut>[];
    final refNow = now ?? DateTime.now();
    final sorted = List<HabitShortcut>.from(_cachedHabits)
      ..sort((a, b) => b.scoreAt(refNow).compareTo(a.scoreAt(refNow)));
    return sorted.take(limit).toList(growable: false);
  }

  /// Combines user's personal RFM habits with contextual time-of-day super-app suggestions
  /// (inspired by MoMo, Grab, Revolut & Todoist). Labels stay concise (`<= 16` chars).
  static List<({String label, String command, bool isPersonalHabit})>
  contextualSmartChips(DateTime now, {int maxCount = 4}) {
    final results = <({String label, String command, bool isPersonalHabit})>[];
    final seenCommands = <String>{};

    for (final habit in topRankedHabits(now: now, limit: 2)) {
      final shortLabel = habit.label.length > 16
          ? '${habit.label.substring(0, 15)}…'
          : habit.label;
      results.add((
        label: shortLabel,
        command: habit.commandText,
        isPersonalHabit: true,
      ));
      seenCommands.add(habit.commandText.toLowerCase());
    }

    final h = now.hour;
    final defaults = switch (h) {
      >= 5 && < 11 => const <(String, String)>[
        ('Cà phê 35k', 'Cà phê 35k'),
        ('Ăn sáng 45k', 'Ăn sáng 45k'),
        ('Đổ xăng 80k', 'Đổ xăng 80k'),
        ('Lịch họp 9h', 'Họp nhóm 9h sáng nay'),
      ],
      >= 11 && < 14 => const <(String, String)>[
        ('Cà phê 35k', 'Cà phê 35k'),
        ('Ăn trưa 55k', 'Ăn trưa 55k'),
        ('Chia cơm nhóm', 'Ăn trưa 240k chia 4 người'),
        ('Nhắc việc chiều', 'Nhắc gửi báo cáo chiều nay'),
      ],
      >= 14 && < 18 => const <(String, String)>[
        ('Cà phê 35k', 'Cà phê 35k'),
        ('Đổ xăng 80k', 'Đổ xăng 80k'),
        ('Lịch sáng mai', 'Họp dự án 9h sáng mai'),
        ('Nhắc đóng điện', 'Nhắc đóng tiền điện tối nay'),
      ],
      _ => const <(String, String)>[
        ('Cà phê 35k', 'Cà phê 35k'),
        ('Ăn tối 120k', 'Ăn tối gia đình 120k'),
        ('Mua sữa, trứng', 'Đi chợ mua sữa tươi, trứng gà'),
        ('Lịch 8h30 mai', 'Lịch làm việc 8h30 sáng mai'),
      ],
    };

    for (final item in defaults) {
      if (results.length >= maxCount) break;
      if (seenCommands.add(item.$2.toLowerCase())) {
        results.add((label: item.$1, command: item.$2, isPersonalHabit: false));
      }
    }

    return results;
  }

  /// Generates instant `.000` / `.0000` / `.000.000` Vietnamese VND completions when a user
  /// types short digits (e.g. `"45"` -> `[45.000, 450.000, 4.500.000]`).
  static List<(int amountMinor, String label)> vndZeroPadSuggestions(
    String rawInput,
  ) {
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
