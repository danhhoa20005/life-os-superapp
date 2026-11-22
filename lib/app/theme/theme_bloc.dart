import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Strict `Bloc<ThemeEvent, ThemeState>` — NEVER uses Cubit.
sealed class ThemeEvent extends Equatable {
  const ThemeEvent();

  @override
  List<Object?> get props => [];
}

final class ThemeModeChanged extends ThemeEvent {
  final ThemeMode themeMode;
  const ThemeModeChanged(this.themeMode);

  @override
  List<Object?> get props => [themeMode];
}

final class HighContrastToggled extends ThemeEvent {
  final bool enabled;
  const HighContrastToggled(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

@immutable
final class ThemeState extends Equatable {
  final ThemeMode themeMode;
  final bool highContrast;

  const ThemeState({
    this.themeMode = ThemeMode.system,
    this.highContrast = false,
  });

  ThemeState copyWith({
    ThemeMode? themeMode,
    bool? highContrast,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      highContrast: highContrast ?? this.highContrast,
    );
  }

  @override
  List<Object?> get props => [themeMode, highContrast];
}

class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  ThemeBloc() : super(const ThemeState()) {
    on<ThemeModeChanged>(_onThemeModeChanged, transformer: sequential());
    on<HighContrastToggled>(_onHighContrastToggled, transformer: sequential());
  }

  void _onThemeModeChanged(ThemeModeChanged event, Emitter<ThemeState> emit) {
    emit(state.copyWith(themeMode: event.themeMode));
  }

  void _onHighContrastToggled(HighContrastToggled event, Emitter<ThemeState> emit) {
    emit(state.copyWith(highContrast: event.enabled));
  }
}
