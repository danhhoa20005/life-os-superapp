import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../domain/motion_sample_spec.dart';

// ── Events ─────────────────────────────────────────────────────────────────
sealed class MotionGalleryEvent extends Equatable {
  const MotionGalleryEvent();

  @override
  List<Object?> get props => const [];
}

final class MotionGalleryCategorySelected extends MotionGalleryEvent {
  final MotionSampleCategory? category;
  const MotionGalleryCategorySelected(this.category);

  @override
  List<Object?> get props => [category];
}

final class MotionGalleryQueryChanged extends MotionGalleryEvent {
  final String query;
  const MotionGalleryQueryChanged(this.query);

  @override
  List<Object?> get props => [query];
}

final class MotionGallerySpeedChanged extends MotionGalleryEvent {
  final double speedFactor;
  const MotionGallerySpeedChanged(this.speedFactor);

  @override
  List<Object?> get props => [speedFactor];
}

final class MotionGalleryReplayTriggered extends MotionGalleryEvent {
  const MotionGalleryReplayTriggered();
}

final class MotionGalleryActiveSampleSelected extends MotionGalleryEvent {
  final String? sampleId;
  const MotionGalleryActiveSampleSelected(this.sampleId);

  @override
  List<Object?> get props => [sampleId];
}

// ── State ──────────────────────────────────────────────────────────────────
final class MotionGalleryState extends Equatable {
  final MotionSampleCategory? selectedCategory;
  final String searchQuery;
  final double speedFactor;
  final int replaySeed;
  final String? activeSampleId;

  const MotionGalleryState({
    this.selectedCategory,
    this.searchQuery = '',
    this.speedFactor = 1.0,
    this.replaySeed = 1,
    this.activeSampleId,
  });

  MotionGalleryState copyWith({
    MotionSampleCategory? Function()? selectedCategory,
    String? searchQuery,
    double? speedFactor,
    int? replaySeed,
    String? Function()? activeSampleId,
  }) {
    return MotionGalleryState(
      selectedCategory: selectedCategory != null
          ? selectedCategory()
          : this.selectedCategory,
      searchQuery: searchQuery ?? this.searchQuery,
      speedFactor: speedFactor ?? this.speedFactor,
      replaySeed: replaySeed ?? this.replaySeed,
      activeSampleId: activeSampleId != null
          ? activeSampleId()
          : this.activeSampleId,
    );
  }

  @override
  List<Object?> get props => [
    selectedCategory,
    searchQuery,
    speedFactor,
    replaySeed,
    activeSampleId,
  ];
}

/// Strictly `flutter_bloc` (0% Cubit, 0% per-frame events) managing high-level
/// filter, playback speed (`0.25x / 0.5x / 1.0x`), and sample selection state.
class MotionGalleryBloc extends Bloc<MotionGalleryEvent, MotionGalleryState> {
  MotionGalleryBloc() : super(const MotionGalleryState()) {
    on<MotionGalleryCategorySelected>(
      (event, emit) =>
          emit(state.copyWith(selectedCategory: () => event.category)),
      transformer: sequential(),
    );
    on<MotionGalleryQueryChanged>(
      (event, emit) => emit(state.copyWith(searchQuery: event.query)),
      transformer: restartable(),
    );
    on<MotionGallerySpeedChanged>(
      (event, emit) => emit(
        state.copyWith(speedFactor: event.speedFactor.clamp(0.25, 2.0)),
      ),
      transformer: sequential(),
    );
    on<MotionGalleryReplayTriggered>(
      (event, emit) => emit(state.copyWith(replaySeed: state.replaySeed + 1)),
      transformer: sequential(),
    );
    on<MotionGalleryActiveSampleSelected>(
      (event, emit) =>
          emit(state.copyWith(activeSampleId: () => event.sampleId)),
      transformer: sequential(),
    );
  }
}
