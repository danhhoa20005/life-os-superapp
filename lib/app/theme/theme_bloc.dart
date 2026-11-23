import 'dart:convert';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Strict `Bloc<ThemeEvent, ThemeState>` — NEVER uses Cubit.
sealed class ThemeEvent extends Equatable {
  const ThemeEvent();

  @override
  List<Object?> get props => [];
}

final class ThemeHydratedFromDisk extends ThemeEvent {
  const ThemeHydratedFromDisk();
}

final class ThemeModeChanged extends ThemeEvent {
  final ThemeMode themeMode;
  const ThemeModeChanged(this.themeMode);

  @override
  List<Object?> get props => [themeMode];
}

final class TextScaleChanged extends ThemeEvent {
  final double textScale;
  const TextScaleChanged(this.textScale);

  @override
  List<Object?> get props => [textScale];
}

final class CompactDensityToggled extends ThemeEvent {
  final bool compactDensity;
  const CompactDensityToggled(this.compactDensity);

  @override
  List<Object?> get props => [compactDensity];
}

final class HighContrastToggled extends ThemeEvent {
  final bool enabled;
  const HighContrastToggled(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

@immutable
final class ThemeState extends Equatable {
  /// Defaults to signature Emerald-Mint Light Mode (`ThemeMode.light`) so dark-OS
  /// phones still open in clean Light Mode unless the user selects Dark or System.
  final ThemeMode themeMode;

  /// Global user-controlled font scale (`0.80` – `1.25`). Defaults to `0.92` for
  /// crisp spatial density without text truncation on compact mobile screens.
  final double textScale;

  /// Spatial layout optimization (`true` = compact airy padding & 4-col Super App dock).
  final bool compactDensity;

  final bool highContrast;

  const ThemeState({
    this.themeMode = ThemeMode.light,
    this.textScale = 0.92,
    this.compactDensity = true,
    this.highContrast = false,
  });

  int get textScalePercent => (textScale * 100).round();

  String get themeModeLabel => switch (themeMode) {
    ThemeMode.light => 'Sáng',
    ThemeMode.dark => 'Tối',
    ThemeMode.system => 'Theo hệ thống',
  };

  ThemeState copyWith({
    ThemeMode? themeMode,
    double? textScale,
    bool? compactDensity,
    bool? highContrast,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      textScale: (textScale ?? this.textScale).clamp(0.80, 1.25),
      compactDensity: compactDensity ?? this.compactDensity,
      highContrast: highContrast ?? this.highContrast,
    );
  }

  @override
  List<Object?> get props => [
    themeMode,
    textScale,
    compactDensity,
    highContrast,
  ];
}

class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  final bool _persistToDisk;

  ThemeBloc({bool? persistToDisk})
    : _persistToDisk =
          persistToDisk ??
          (!kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST')),
      super(const ThemeState()) {
    on<ThemeHydratedFromDisk>(_onHydrate, transformer: sequential());
    on<ThemeModeChanged>(_onThemeModeChanged, transformer: sequential());
    on<TextScaleChanged>(_onTextScaleChanged, transformer: sequential());
    on<CompactDensityToggled>(
      _onCompactDensityToggled,
      transformer: sequential(),
    );
    on<HighContrastToggled>(_onHighContrastToggled, transformer: sequential());
  }

  static File _resolvePrefsFile() {
    final tempParent = Directory.systemTemp.parent;
    final filesDir = Directory(
      '${tempParent.path}${Platform.pathSeparator}files',
    );
    if (filesDir.existsSync()) {
      return File(
        '${filesDir.path}${Platform.pathSeparator}lifeos_ui_prefs.json',
      );
    }
    return File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}lifeos_ui_prefs.json',
    );
  }

  Future<void> _saveState(ThemeState s) async {
    if (!_persistToDisk || kIsWeb) return;
    try {
      final file = _resolvePrefsFile();
      await file.writeAsString(
        jsonEncode({
          'themeMode': s.themeMode.name,
          'textScale': s.textScale,
          'compactDensity': s.compactDensity,
          'highContrast': s.highContrast,
        }),
      );
    } catch (_) {}
  }

  Future<void> _onHydrate(
    ThemeHydratedFromDisk event,
    Emitter<ThemeState> emit,
  ) async {
    if (!_persistToDisk || kIsWeb) return;
    try {
      final file = _resolvePrefsFile();
      if (!file.existsSync()) return;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final rawMode = map['themeMode'] as String?;
      final mode = ThemeMode.values.firstWhere(
        (m) => m.name == rawMode,
        orElse: () => ThemeMode.light,
      );
      final scale = (map['textScale'] as num?)?.toDouble() ?? 0.92;
      final compact = map['compactDensity'] != false;
      final hc = map['highContrast'] == true;
      emit(
        state.copyWith(
          themeMode: mode,
          textScale: scale,
          compactDensity: compact,
          highContrast: hc,
        ),
      );
    } catch (_) {}
  }

  Future<void> _onThemeModeChanged(
    ThemeModeChanged event,
    Emitter<ThemeState> emit,
  ) async {
    final next = state.copyWith(themeMode: event.themeMode);
    emit(next);
    await _saveState(next);
  }

  Future<void> _onTextScaleChanged(
    TextScaleChanged event,
    Emitter<ThemeState> emit,
  ) async {
    final next = state.copyWith(textScale: event.textScale);
    emit(next);
    await _saveState(next);
  }

  Future<void> _onCompactDensityToggled(
    CompactDensityToggled event,
    Emitter<ThemeState> emit,
  ) async {
    final next = state.copyWith(compactDensity: event.compactDensity);
    emit(next);
    await _saveState(next);
  }

  Future<void> _onHighContrastToggled(
    HighContrastToggled event,
    Emitter<ThemeState> emit,
  ) async {
    final next = state.copyWith(highContrast: event.enabled);
    emit(next);
    await _saveState(next);
  }
}
