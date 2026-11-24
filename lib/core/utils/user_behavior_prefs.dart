import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../services/native_secure_vault_bridge.dart';
import 'vnd_amount.dart';

/// Represents a learned user habit ranked by Recency × Frequency × Circadian Time Affinity
/// (inspired by MoMo, Grab, Revolut & Todoist quick-replay chips).
class HabitShortcut extends Equatable {
  final String id;
  final String label;
  final String commandText;
  final String categoryName;
  final int amountMinor;
  final int frequency;
  final int lastUsedEpochMs;
  final int typicalHour;

  const HabitShortcut({
    required this.id,
    required this.label,
    required this.commandText,
    this.categoryName = '',
    this.amountMinor = 0,
    this.frequency = 1,
    required this.lastUsedEpochMs,
    required this.typicalHour,
  });

  /// Computes behavioral relevance score at [now] combining frequency, 14-day recency decay,
  /// and ±2h circadian time-of-day affinity.
  double scoreAt(DateTime now) {
    final freqScore = frequency * 2.2;
    final ageHours =
        ((now.millisecondsSinceEpoch - lastUsedEpochMs) / 3600000.0).clamp(
          0.0,
          720.0,
        );
    final recencyScore = (1.0 - (ageHours / 336.0)).clamp(0.0, 1.0) * 4.0;
    final hourDiff = (now.hour - typicalHour).abs();
    final wrappedHourDiff = hourDiff > 12 ? 24 - hourDiff : hourDiff;
    final circadianBonus = wrappedHourDiff <= 2
        ? 3.2
        : (wrappedHourDiff <= 4 ? 1.2 : 0.0);
    return freqScore + recencyScore + circadianBonus;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    'commandText': commandText,
    'categoryName': categoryName,
    'amountMinor': amountMinor,
    'frequency': frequency,
    'lastUsedEpochMs': lastUsedEpochMs,
    'typicalHour': typicalHour,
  };

  factory HabitShortcut.fromJson(Map<String, dynamic> json) {
    return HabitShortcut(
      id: (json['id'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      commandText: (json['commandText'] as String?) ?? '',
      categoryName: (json['categoryName'] as String?) ?? '',
      amountMinor: (json['amountMinor'] as num?)?.toInt() ?? 0,
      frequency: (json['frequency'] as num?)?.toInt() ?? 1,
      lastUsedEpochMs: (json['lastUsedEpochMs'] as num?)?.toInt() ?? 0,
      typicalHour: (json['typicalHour'] as num?)?.toInt() ?? 12,
    );
  }

  @override
  List<Object?> get props => [
    id,
    label,
    commandText,
    categoryName,
    amountMinor,
    frequency,
    lastUsedEpochMs,
    typicalHour,
  ];
}

/// Persists everyday user habits & preferences (last-used wallet, privacy balance mask,
/// pinned home shortcuts, RFM habit memory) and provides Vietnamese shorthand & circadian helpers.
abstract final class UserBehaviorPrefs {
  static const String _keyLastWallet = 'ux_last_used_wallet_id';
  static const String _keyPinnedShortcuts = 'ux_home_pinned_shortcuts_v1';
  static const String _keyHideBalances = 'ux_privacy_hide_balances';
  static const String _keyHabitActions = 'ux_habit_actions_rfm_v1';
  static const String _keySecurityPin = 'sec_app_pin_code_v1';
  static const String _keyPermissionsPopupDismissed =
      'ux_permissions_popup_dismissed_v1';

  static String? _cachedLastWalletId;
  static bool? _cachedHideBalances;
  static String? _cachedAppPin;
  static bool? _cachedPermissionsPopupDismissed;
  static List<HabitShortcut> _cachedHabits = const <HabitShortcut>[];

  static Future<void> resetForTest() async {
    _cachedLastWalletId = null;
    _cachedHideBalances = null;
    _cachedAppPin = null;
    _cachedPermissionsPopupDismissed = null;
    _cachedHabits = const <HabitShortcut>[];
    await NativeSecureVaultBridge.instance.deleteSecret(_keyLastWallet);
    await NativeSecureVaultBridge.instance.deleteSecret(_keyPinnedShortcuts);
    await NativeSecureVaultBridge.instance.deleteSecret(_keyHideBalances);
    await NativeSecureVaultBridge.instance.deleteSecret(_keyHabitActions);
    await NativeSecureVaultBridge.instance.deleteSecret(_keySecurityPin);
    await NativeSecureVaultBridge.instance.deleteSecret(
      _keyPermissionsPopupDismissed,
    );
  }

  static Future<bool> hasDismissedPermissionsPopup() async {
    if (_cachedPermissionsPopupDismissed != null) {
      return _cachedPermissionsPopupDismissed!;
    }
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _keyPermissionsPopupDismissed,
    );
    _cachedPermissionsPopupDismissed = raw == '1';
    return _cachedPermissionsPopupDismissed!;
  }

  static Future<void> markPermissionsPopupDismissed([
    bool dismissed = true,
  ]) async {
    _cachedPermissionsPopupDismissed = dismissed;
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _keyPermissionsPopupDismissed,
      value: dismissed ? '1' : '0',
    );
  }

  static Future<void> saveAppPinCode(String? pin) async {
    final cleaned = (pin ?? '').trim();
    if (cleaned.isEmpty) {
      _cachedAppPin = null;
      await NativeSecureVaultBridge.instance.deleteSecret(_keySecurityPin);
      return;
    }
    _cachedAppPin = cleaned;
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _keySecurityPin,
      value: cleaned,
    );
  }

  static Future<String?> loadAppPinCode() async {
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _keySecurityPin,
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
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _keyPinnedShortcuts,
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
      key: _keyHideBalances,
      value: hide ? '1' : '0',
    );
  }

  static Future<bool> loadHideBalances() async {
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _keyHideBalances,
    );
    if (raw != null) {
      _cachedHideBalances = raw == '1';
    }
    return _cachedHideBalances ?? false;
  }

  /// Loads persisted RFM habit shortcuts from hardware-backed local storage.
  static Future<List<HabitShortcut>> loadHabitShortcuts() async {
    final raw = await NativeSecureVaultBridge.instance.readSecret(
      _keyHabitActions,
    );
    if (raw == null || raw.trim().isEmpty) {
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

  /// Records a completed quick action into RFM habit memory (max 16 habits).
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

    final refNow = now ?? DateTime.now();
    final canonicalId = cleanLabel.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final mutable = List<HabitShortcut>.from(_cachedHabits);
    final idx = mutable.indexWhere((h) => h.id == canonicalId);

    if (idx >= 0) {
      final prev = mutable[idx];
      mutable[idx] = HabitShortcut(
        id: canonicalId,
        label: cleanLabel,
        commandText: cleanCmd,
        categoryName: categoryName.isNotEmpty ? categoryName : prev.categoryName,
        amountMinor: amountMinor > 0 ? amountMinor : prev.amountMinor,
        frequency: prev.frequency + 1,
        lastUsedEpochMs: refNow.millisecondsSinceEpoch,
        typicalHour: ((prev.typicalHour + refNow.hour) / 2).round(),
      );
    } else {
      mutable.insert(
        0,
        HabitShortcut(
          id: canonicalId,
          label: cleanLabel,
          commandText: cleanCmd,
          categoryName: categoryName,
          amountMinor: amountMinor,
          frequency: 1,
          lastUsedEpochMs: refNow.millisecondsSinceEpoch,
          typicalHour: refNow.hour,
        ),
      );
    }

    mutable.sort((a, b) => b.scoreAt(refNow).compareTo(a.scoreAt(refNow)));
    if (mutable.length > 16) {
      mutable.removeRange(16, mutable.length);
    }
    _cachedHabits = List<HabitShortcut>.unmodifiable(mutable);

    await NativeSecureVaultBridge.instance.writeSecret(
      key: _keyHabitActions,
      value: jsonEncode(_cachedHabits.map((h) => h.toJson()).toList()),
    );
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
        results.add((
          label: item.$1,
          command: item.$2,
          isPersonalHabit: false,
        ));
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
