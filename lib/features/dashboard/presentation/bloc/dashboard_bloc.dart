import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/dashboard_entities.dart';
import '../../domain/repositories/dashboard_repository.dart';

sealed class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

final class DashboardWatchStarted extends DashboardEvent {
  final String userId;
  final String? familyId;

  const DashboardWatchStarted({required this.userId, this.familyId});

  @override
  List<Object?> get props => [userId, familyId];
}

final class DashboardState extends Equatable {
  final bool isLoading;
  final TodayDashboardEntity data;
  final Failure? failure;

  const DashboardState({
    this.isLoading = false,
    this.data = TodayDashboardEntity.empty,
    this.failure,
  });

  DashboardState copyWith({
    bool? isLoading,
    TodayDashboardEntity? data,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      data: data ?? this.data,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => [isLoading, data, failure];
}

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final DashboardRepository _repository;

  DashboardBloc({required DashboardRepository repository})
      : _repository = repository,
        super(const DashboardState()) {
    on<DashboardWatchStarted>(_onWatchStarted, transformer: restartable());
  }

  Future<void> _onWatchStarted(
    DashboardWatchStarted event,
    Emitter<DashboardState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));
    await emit.forEach<Result<TodayDashboardEntity>>(
      _repository.watchTodayDashboard(userId: event.userId, familyId: event.familyId),
      onData: (res) => res.fold(
        (f) => state.copyWith(isLoading: false, failure: f),
        (d) => state.copyWith(isLoading: false, data: d, clearFailure: true),
      ),
    );
  }
}
