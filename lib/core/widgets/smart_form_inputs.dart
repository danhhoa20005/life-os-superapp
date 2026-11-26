import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../motion/lifeos_motion_tokens.dart';
import '../motion/widgets/lifeos_animated_visibility.dart';
import '../utils/user_behavior_prefs.dart';
import '../utils/vnd_amount.dart';

/// Pure-Dart exact integer VND parser supporting standard formatted numbers (`35000`, `35.000`),
/// shorthand (`35k`, `1tr2`, `1tr25`, `1.5tr`), Vietnamese unit phrases (`500 nghìn`,
/// `1 triệu 200 nghìn`, `1 triệu rưỡi`, `1 tỷ 200 triệu`), and spoken phrases (`năm trăm nghìn`).
///
/// Always rejects negatives, zero, out-of-range values, and mixed non-currency text
/// inside dedicated numeric/amount inputs so validation never silently misparses.
abstract final class SmartVndAmountParser {
  static const Map<String, int> _spokenDigits = <String, int>{
    'không': 0,
    'khong': 0,
    'linh': 0,
    'lẻ': 0,
    'le': 0,
    'một': 1,
    'mot': 1,
    'mốt': 1,
    'hai': 2,
    'ba': 3,
    'bốn': 4,
    'bon': 4,
    'tư': 4,
    'tu': 4,
    'năm': 5,
    'nam': 5,
    'lăm': 5,
    'lam': 5,
    'nhăm': 5,
    'sáu': 6,
    'sau': 6,
    'bảy': 7,
    'bay': 7,
    'bẩy': 7,
    'tám': 8,
    'tam': 8,
    'chín': 9,
    'chin': 9,
    'mười': 10,
    'muoi': 10,
  };

  static const Set<String> _nonStandaloneTokens = <String>{
    'không',
    'khong',
    'linh',
    'lẻ',
    'le',
    'mốt',
    'tư',
    'tu',
    'lăm',
    'lam',
    'nhăm',
  };

  static final RegExp _negativeRegex = RegExp(
    r'^(?:[-−]|âm\b|am\b)',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _trailingCurrencyRegex = RegExp(
    r'(?:\s*(?:vnđ|vnd|đồng|dong|₫|đ)|(?<=[\d\s])d)\s*$',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _spacedThousandsRegex = RegExp(r'^\d{1,3}(?:\s\d{3})+$');

  static final RegExp _billionCompoundRegex = RegExp(
    r'^(\d+)(?:[.,](\d{1,3}))?\s*(?:tỷ|ty)(?:\s*(?:(\d{1,3})\s*(?:triệu|trieu|tr)?|(rưỡi|ruoi)))?$',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _millionCompoundRegex = RegExp(
    r'^(\d+)(?:[.,](\d{1,6}))?\s*(?:tr|triệu|trieu|củ|cu)(?:\s*(?:(\d{1,3})\s*(nghìn|nghin|ngàn|ngan|k)?|(rưỡi|ruoi)))?$',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _thousandRegex = RegExp(
    r'^(\d+)(?:[.,](\d{1,3}))?\s*(?:k|nghìn|nghin|ngàn|ngan)(?:\s*(\d{1,2}))?$',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _spokenPhraseRegex = RegExp(
    r'(?<![\p{L}\p{N}])((?:(?:không|khong|một|mot|mốt|hai|ba|bốn|bon|tư|tu|năm|nam|lăm|lam|nhăm|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin|mười|muoi|mươi|trăm|tram|linh|lẻ|le)\s+){1,6})(tỷ|ty|triệu|trieu|tr|củ|cu|nghìn|nghin|ngàn|ngan)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  /// Parses [raw] into exact positive integer VND minor units, or `null` if invalid.
  static int? tryParse(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return null;
    if (_negativeRegex.hasMatch(trimmed)) return null;

    // 1. Try canonical VndAmount parser first for standard integer / formatted inputs.
    final direct = VndAmount.tryParseInput(trimmed);
    if (direct != null) return direct;

    // Strip trailing currency unit ("₫", "đ", "VND", "đồng") after digits/words.
    var s = trimmed.replaceFirst(_trailingCurrencyRegex, '').trim();
    if (s.isEmpty || _negativeRegex.hasMatch(s)) return null;

    // 2. Spaced thousands like "35 000" or "1 200 000".
    if (_spacedThousandsRegex.hasMatch(s)) {
      final compact = s.replaceAll(' ', '');
      return VndAmount.tryParseInput(compact);
    }

    // 3. Re-try VndAmount after stripping trailing "đồng" / "dong" / "d".
    final afterSuffix = VndAmount.tryParseInput(s);
    if (afterSuffix != null) return afterSuffix;

    // 4. Normalize common spoken prefixes ("nửa triệu", "một triệu hai trăm nghìn", etc.).
    s = _normalizeSpokenUnits(s);

    // 5. Billion expressions: "1 tỷ", "1ty2", "1 tỷ 200 triệu", "1 tỷ rưỡi".
    final bMatch = _billionCompoundRegex.firstMatch(s);
    if (bMatch != null) {
      final whole = int.tryParse(bMatch.group(1) ?? '');
      if (whole == null) return null;
      final dec = bMatch.group(2);
      final tailDigits = bMatch.group(3);
      final half = bMatch.group(4);
      if (dec != null && (tailDigits != null || half != null)) return null;

      var total = whole * 1000000000;
      if (dec != null && dec.isNotEmpty) {
        final padded = dec.padRight(9, '0').substring(0, 9);
        total += int.parse(padded);
      } else if (half != null) {
        total += 500000000;
      } else if (tailDigits != null && tailDigits.isNotEmpty) {
        final tailVal = int.tryParse(tailDigits) ?? 0;
        final hasExplicitMil =
            s.toLowerCase().contains('triệu') ||
            s.toLowerCase().contains('trieu') ||
            RegExp(r'\btr\b', caseSensitive: false).hasMatch(s);
        if (hasExplicitMil) {
          total += tailVal * 1000000;
        } else {
          final scale = switch (tailDigits.length) {
            1 => 100000000,
            2 => 10000000,
            _ => 1000000,
          };
          total += tailVal * scale;
        }
      }
      return (total > 0 && total <= VndAmount.maxAllowedMinor) ? total : null;
    }

    // 6. Million expressions: "1tr2", "1.5tr", "1 triệu 200 nghìn", "1 triệu rưỡi".
    final mMatch = _millionCompoundRegex.firstMatch(s);
    if (mMatch != null) {
      final whole = int.tryParse(mMatch.group(1) ?? '');
      if (whole == null) return null;
      final dec = mMatch.group(2);
      final tailDigits = mMatch.group(3);
      final tailUnit = mMatch.group(4);
      final half = mMatch.group(5);
      if (dec != null && (tailDigits != null || half != null)) return null;

      var total = whole * 1000000;
      if (dec != null && dec.isNotEmpty) {
        final padded = dec.padRight(6, '0').substring(0, 6);
        total += int.parse(padded);
      } else if (half != null) {
        total += 500000;
      } else if (tailDigits != null && tailDigits.isNotEmpty) {
        final tailVal = int.tryParse(tailDigits) ?? 0;
        if (tailUnit != null && tailUnit.isNotEmpty) {
          total += tailVal * 1000;
        } else {
          final scale = switch (tailDigits.length) {
            1 => 100000,
            2 => 10000,
            _ => 1000,
          };
          total += tailVal * scale;
        }
      }
      return (total > 0 && total <= VndAmount.maxAllowedMinor) ? total : null;
    }

    // 7. Thousand expressions: "35k", "35.5k", "35k5", "500 nghìn", "500 ngàn".
    final kMatch = _thousandRegex.firstMatch(s);
    if (kMatch != null) {
      final whole = int.tryParse(kMatch.group(1) ?? '');
      if (whole == null) return null;
      final dec = kMatch.group(2);
      final tail = kMatch.group(3);
      if (dec != null && tail != null) return null;

      var total = whole * 1000;
      if (dec != null && dec.isNotEmpty) {
        final padded = dec.padRight(3, '0').substring(0, 3);
        total += int.parse(padded);
      } else if (tail != null && tail.isNotEmpty) {
        final scale = tail.length == 1 ? 100 : 10;
        total += (int.tryParse(tail) ?? 0) * scale;
      }
      return (total > 0 && total <= VndAmount.maxAllowedMinor) ? total : null;
    }

    return null;
  }

  static String _normalizeSpokenUnits(String input) {
    var s = input
        .replaceAll(
          RegExp(
            r'^(?:nửa|nua)\s+(?:triệu|trieu|củ|cu)$',
            caseSensitive: false,
            unicode: true,
          ),
          '500k',
        )
        .replaceAll(
          RegExp(
            r'^(?:nửa|nua)\s+(?:tỷ|ty)$',
            caseSensitive: false,
            unicode: true,
          ),
          '500tr',
        );

    s = s.replaceAllMapped(_spokenPhraseRegex, (m) {
      final phrase = m.group(1) ?? '';
      final unit = m.group(2) ?? '';
      final val = _parseSmallSpokenInt(phrase);
      if (val == null || val <= 0) return m.group(0)!;
      return '$val $unit';
    });

    // Handle trailing spoken hundred shorthand after "triệu", e.g., "1 triệu hai" -> "1 triệu 2"
    final trailingSpokenMil = RegExp(
      r'^(\d+\s*(?:triệu|trieu|tr))\s+(một|mot|hai|ba|bốn|bon|tư|tu|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)$',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(s);
    if (trailingSpokenMil != null) {
      final digitWord = (trailingSpokenMil.group(2) ?? '').toLowerCase();
      final d = _spokenDigits[digitWord];
      if (d != null && d > 0) {
        s = '${trailingSpokenMil.group(1)} $d';
      }
    }

    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static int? _parseSmallSpokenInt(String phrase) {
    final tokens = phrase
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;
    if (tokens.length == 1 && _nonStandaloneTokens.contains(tokens.first)) {
      return null;
    }

    var hundreds = 0;
    var tens = 0;
    var ones = 0;
    var i = 0;

    if (i + 1 < tokens.length &&
        (tokens[i + 1] == 'trăm' || tokens[i + 1] == 'tram')) {
      final h = _spokenDigits[tokens[i]];
      if (h == null || h <= 0 || h > 9) return null;
      hundreds = h * 100;
      i += 2;
      if (i < tokens.length &&
          (tokens[i] == 'linh' || tokens[i] == 'lẻ' || tokens[i] == 'le')) {
        i++;
      }
    }

    if (i < tokens.length) {
      if (tokens[i] == 'mười' || tokens[i] == 'muoi') {
        tens = 10;
        i++;
        if (i < tokens.length && _spokenDigits.containsKey(tokens[i])) {
          ones = _spokenDigits[tokens[i]]!;
          i++;
        }
      } else if (i + 1 < tokens.length &&
          (tokens[i + 1] == 'mươi' || tokens[i + 1] == 'muoi')) {
        final t = _spokenDigits[tokens[i]];
        if (t == null || t <= 0 || t > 9) return null;
        tens = t * 10;
        i += 2;
        if (i < tokens.length && _spokenDigits.containsKey(tokens[i])) {
          ones = _spokenDigits[tokens[i]]!;
          i++;
        }
      } else if (i + 1 == tokens.length - 1 &&
          hundreds == 0 &&
          _spokenDigits.containsKey(tokens[i]) &&
          (_spokenDigits[tokens[i]] ?? 0) >= 2 &&
          (_spokenDigits[tokens[i]] ?? 0) <= 9 &&
          const {
            'mốt',
            'tư',
            'tu',
            'lăm',
            'lam',
            'nhăm',
          }.contains(tokens[i + 1])) {
        tens = _spokenDigits[tokens[i]]! * 10;
        ones = _spokenDigits[tokens[i + 1]]!;
        i += 2;
      } else if (_spokenDigits.containsKey(tokens[i])) {
        ones = _spokenDigits[tokens[i]]!;
        i++;
      }
    }

    if (i != tokens.length) return null;
    final total = hundreds + tens + ones;
    return total > 0 ? total : null;
  }
}

/// Reusable Vietnamese VND Smart Amount Input Field:
/// - Accepts `35000`, `35k`, `1tr2`, `1 triệu 200 nghìn`, `500 nghìn` via [TextInputType.text]
/// - Shows non-destructive tappable zero-pad suggestion chips (`Key('vnd_zero_pad_<amount>')`)
///   when short digits like `"35"` are entered (NEVER auto-mutates text without user tap!)
/// - Renders live confirmation readout (`'Số tiền sẽ lưu: 35.000 ₫'`) with tabular numerals
///   or inline validation error when invalid.
class LifeOsVndSmartAmountField extends StatefulWidget {
  final Key? fieldKey;
  final TextEditingController? controller;
  final String labelText;
  final String hintText;
  final bool autofocus;
  final bool allowEmpty;
  final ValueChanged<int?>? onAmountChanged;
  final ValueChanged<String>? onTextChanged;
  final VoidCallback? onSubmitted;

  const LifeOsVndSmartAmountField({
    super.key,
    this.fieldKey,
    this.controller,
    this.labelText = 'Số tiền (VND)',
    this.hintText = 'VD: 35000, 35k, 1tr2',
    this.autofocus = false,
    this.allowEmpty = false,
    this.onAmountChanged,
    this.onTextChanged,
    this.onSubmitted,
  });

  @override
  State<LifeOsVndSmartAmountField> createState() =>
      _LifeOsVndSmartAmountFieldState();
}

class _LifeOsVndSmartAmountFieldState extends State<LifeOsVndSmartAmountField> {
  TextEditingController? _ownedCtrl;
  late TextEditingController _ctrl;
  String _lastObservedText = '';

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
  }

  void _attachController(TextEditingController? external) {
    if (external != null) {
      _ctrl = external;
    } else {
      _ownedCtrl ??= TextEditingController();
      _ctrl = _ownedCtrl!;
    }
    _lastObservedText = _ctrl.text;
    _ctrl.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant LifeOsVndSmartAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _ctrl.removeListener(_onControllerChanged);
      _attachController(widget.controller);
    }
  }

  void _onControllerChanged() {
    final current = _ctrl.text;
    if (current == _lastObservedText) return;
    _lastObservedText = current;
    final parsed = SmartVndAmountParser.tryParse(current);
    widget.onAmountChanged?.call(parsed);
    widget.onTextChanged?.call(current);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _ownedCtrl?.dispose();
    super.dispose();
  }

  void _applySuggestion(int amountMinor) {
    final nextText = '$amountMinor';
    _ctrl.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final raw = _ctrl.text;
    final trimmed = raw.trim();
    final parsed = SmartVndAmountParser.tryParse(raw);
    final isInvalid = trimmed.isNotEmpty && parsed == null;
    final suggestions = RegExp(r'^\d{1,4}$').hasMatch(trimmed)
        ? UserBehaviorPrefs.vndZeroPadSuggestions(trimmed)
        : const <(int, String)>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: widget.fieldKey,
          controller: _ctrl,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          autofocus: widget.autofocus,
          onSubmitted: (_) => widget.onSubmitted?.call(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            suffixText: '₫',
            suffixIcon: trimmed.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Xóa số tiền',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () {
                      _ctrl.clear();
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sug in suggestions)
                Material(
                  color: c.primarySubtle,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: c.primary.withValues(alpha: 0.45)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: Key('vnd_zero_pad_${sug.$1}'),
                    onTap: () => _applySuggestion(sug.$1),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 48,
                        minWidth: 48,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            sug.$2,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: c.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        LifeOsAnimatedVisibility(
          visible: (parsed != null && parsed > 0) || isInvalid,
          duration: LifeOsMotionTokens.micro,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: parsed != null && parsed > 0
                ? Semantics(
                    liveRegion: true,
                    label: 'Số tiền sẽ lưu: ${VndAmount.format(parsed)}',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: c.successSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: c.success.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 17,
                            color: c.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Số tiền sẽ lưu: ${VndAmount.format(parsed)}',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: c.success,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Semantics(
                    liveRegion: true,
                    label:
                        'Số tiền chưa hợp lệ. Hãy nhập dạng 35000, 35k hoặc 1tr2.',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: c.errorSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: c.error.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 17,
                            color: c.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Số tiền chưa hợp lệ (VD: 35000, 35k, 1tr2).',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: c.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Preset Vietnamese relative time options for fast date-time entry.
enum VietnameseRelativeTimePreset {
  in15Minutes('15 phút nữa'),
  today('Hôm nay'),
  tomorrow('Ngày mai'),
  weekend('Cuối tuần'),
  nextMonday('Thứ Hai tuần sau');

  final String labelVi;
  const VietnameseRelativeTimePreset(this.labelVi);
}

/// Pure-Dart deterministic Vietnamese relative date/time resolver with explicit
/// human-readable disambiguation labels (e.g., `'Hiểu là: Thứ Hai, 30/11 lúc 09:00'`).
abstract final class VietnameseRelativeTimeResolver {
  static final DateFormat _ddMmFmt = DateFormat('dd/MM');
  static final DateFormat _hhMmFmt = DateFormat('HH:mm');

  static String weekdayVi(DateTime dt) => switch (dt.weekday) {
    DateTime.monday => 'Thứ Hai',
    DateTime.tuesday => 'Thứ Ba',
    DateTime.wednesday => 'Thứ Tư',
    DateTime.thursday => 'Thứ Năm',
    DateTime.friday => 'Thứ Sáu',
    DateTime.saturday => 'Thứ Bảy',
    DateTime.sunday => 'Chủ Nhật',
    _ => 'Hôm nay',
  };

  static String formatExplanation(DateTime dt) {
    final ddMm = _ddMmFmt.format(dt);
    final hhMm = _hhMmFmt.format(dt);
    return 'Hiểu là: ${weekdayVi(dt)}, $ddMm lúc $hhMm';
  }

  /// Resolves [preset] relative to [now] and returns `(resolved, explanationVi, isAmbiguous)`.
  static (DateTime resolved, String explanationVi, bool isAmbiguous) resolve(
    VietnameseRelativeTimePreset preset,
    DateTime now,
  ) {
    late final DateTime resolved;
    late final bool isAmbiguous;

    switch (preset) {
      case VietnameseRelativeTimePreset.in15Minutes:
        final base = DateTime(
          now.year,
          now.month,
          now.day,
          now.hour,
          now.minute,
        );
        resolved = base.add(const Duration(minutes: 15));
        isAmbiguous = false;
      case VietnameseRelativeTimePreset.today:
        if (now.hour < 19) {
          resolved = DateTime(now.year, now.month, now.day, 20, 0);
        } else if (now.hour < 22) {
          resolved = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
        } else {
          resolved = DateTime(now.year, now.month, now.day, 23, 30);
        }
        isAmbiguous = false;
      case VietnameseRelativeTimePreset.tomorrow:
        resolved = DateTime(now.year, now.month, now.day + 1, 9, 0);
        isAmbiguous = false;
      case VietnameseRelativeTimePreset.weekend:
        final int daysOffset;
        if (now.weekday < DateTime.saturday) {
          daysOffset = DateTime.saturday - now.weekday;
        } else if (now.weekday == DateTime.saturday) {
          daysOffset = now.hour < 9 ? 0 : 1;
        } else {
          daysOffset = 6;
        }
        resolved = DateTime(now.year, now.month, now.day + daysOffset, 9, 0);
        isAmbiguous = true;
      case VietnameseRelativeTimePreset.nextMonday:
        final daysToNextMonday = 8 - now.weekday;
        resolved = DateTime(
          now.year,
          now.month,
          now.day + daysToNextMonday,
          9,
          0,
        );
        isAmbiguous = true;
    }

    return (resolved, formatExplanation(resolved), isAmbiguous);
  }
}

/// Interactive Vietnamese Relative Date & Time Picker with quick chips + direct
/// calendar/clock dialog and an explicit disambiguation preview banner.
class LifeOsRelativeDateTimePicker extends StatelessWidget {
  final DateTime selectedDateTime;
  final VietnameseRelativeTimePreset? selectedPreset;
  final bool isAmbiguous;
  final String? title;
  final void Function(
    DateTime resolved,
    VietnameseRelativeTimePreset? preset,
    bool isAmbiguous,
  )
  onChanged;

  const LifeOsRelativeDateTimePicker({
    super.key,
    required this.selectedDateTime,
    this.selectedPreset,
    this.isAmbiguous = false,
    this.title,
    required this.onChanged,
  });

  Future<void> _pickCustomDateTime(BuildContext context) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null || !context.mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDateTime),
    );
    if (!context.mounted) return;
    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime?.hour ?? selectedDateTime.hour,
      pickedTime?.minute ?? selectedDateTime.minute,
    );
    onChanged(combined, null, false);
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final bannerText = VietnameseRelativeTimeResolver.formatExplanation(
      selectedDateTime,
    );
    final bannerBg = isAmbiguous ? c.warningSubtle : c.primarySubtle;
    final bannerFg = isAmbiguous ? c.warning : c.primary;

    const orderedPresets = <VietnameseRelativeTimePreset>[
      VietnameseRelativeTimePreset.today,
      VietnameseRelativeTimePreset.tomorrow,
      VietnameseRelativeTimePreset.weekend,
      VietnameseRelativeTimePreset.in15Minutes,
      VietnameseRelativeTimePreset.nextMonday,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null && title!.trim().isNotEmpty) ...[
          Text(
            title!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in orderedPresets)
              _buildTimeChip(
                context,
                c: c,
                chipKey: Key('rel_time_${preset.name}'),
                label: preset.labelVi,
                selected: selectedPreset == preset,
                onTap: () {
                  final (dt, _, amb) = VietnameseRelativeTimeResolver.resolve(
                    preset,
                    DateTime.now(),
                  );
                  onChanged(dt, preset, amb);
                },
              ),
            _buildTimeChip(
              context,
              c: c,
              chipKey: const Key('rel_time_custom_btn'),
              label: 'Chọn ngày giờ...',
              icon: Icons.edit_calendar_rounded,
              selected: selectedPreset == null,
              onTap: () => _pickCustomDateTime(context),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          label: bannerText,
          child: Container(
            key: const Key('rel_time_preview_banner'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: bannerBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: bannerFg.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(
                  isAmbiguous
                      ? Icons.event_note_rounded
                      : Icons.schedule_rounded,
                  size: 17,
                  color: bannerFg,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bannerText,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12.8,
                      fontWeight: FontWeight.w700,
                      color: bannerFg,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeChip(
    BuildContext context, {
    required TammySemanticColors c,
    required Key chipKey,
    required String label,
    IconData? icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? c.primarySubtle : c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? c.primary.withValues(alpha: 0.55) : c.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: chipKey,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: c.primary),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? c.primary : c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
