import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../domain/entities/family_entities.dart';
import '../../domain/repositories/family_repository.dart';
import '../../domain/usecases/family_usecases.dart';

sealed class FamilyEvent extends Equatable {
  const FamilyEvent();

  @override
  List<Object?> get props => [];
}

final class FamilySubscriptionRequested extends FamilyEvent {
  final String userId;
  final String? preferredFamilyId;

  const FamilySubscriptionRequested({
    required this.userId,
    this.preferredFamilyId,
  });

  @override
  List<Object?> get props => [userId, preferredFamilyId];
}

final class FamilyShoppingWatchRequested extends FamilyEvent {
  final String familyId;
  const FamilyShoppingWatchRequested(this.familyId);

  @override
  List<Object?> get props => [familyId];
}

final class FamilyCreateSubmitted extends FamilyEvent {
  final String userId;
  final String userName;
  final String familyName;
  final CollaborationSpaceType spaceType;

  const FamilyCreateSubmitted({
    required this.userId,
    required this.userName,
    required this.familyName,
    this.spaceType = CollaborationSpaceType.family,
  });

  @override
  List<Object?> get props => [userId, userName, familyName, spaceType];
}

final class FamilyInviteGenerated extends FamilyEvent {
  final String userId;
  final String familyId;
  final String familyName;
  final CollaborationSpaceType spaceType;
  final String? invitedByName;
  final String? inviteeName;
  final String? inviteeContact;

  const FamilyInviteGenerated({
    required this.userId,
    required this.familyId,
    required this.familyName,
    this.spaceType = CollaborationSpaceType.family,
    this.invitedByName,
    this.inviteeName,
    this.inviteeContact,
  });

  @override
  List<Object?> get props => [
    userId,
    familyId,
    familyName,
    spaceType,
    invitedByName,
    inviteeName,
    inviteeContact,
  ];
}

final class FamilyInvitePreviewRequested extends FamilyEvent {
  final String inviteCode;
  const FamilyInvitePreviewRequested(this.inviteCode);

  @override
  List<Object?> get props => [inviteCode];
}

final class FamilyInvitePreviewCleared extends FamilyEvent {
  const FamilyInvitePreviewCleared();
}

final class FamilyInviteRevokeRequested extends FamilyEvent {
  final String actorUserId;
  final String familyId;
  final String inviteCode;

  const FamilyInviteRevokeRequested({
    required this.actorUserId,
    required this.familyId,
    required this.inviteCode,
  });

  @override
  List<Object?> get props => [actorUserId, familyId, inviteCode];
}

final class FamilyMemberRoleUpdated extends FamilyEvent {
  final String actorUserId;
  final String familyId;
  final String targetUserId;
  final String targetName;
  final HouseholdRole newRole;

  const FamilyMemberRoleUpdated({
    required this.actorUserId,
    required this.familyId,
    required this.targetUserId,
    required this.targetName,
    required this.newRole,
  });

  @override
  List<Object?> get props => [
    actorUserId,
    familyId,
    targetUserId,
    targetName,
    newRole,
  ];
}

final class FamilyMemberRemoved extends FamilyEvent {
  final String actorUserId;
  final String familyId;
  final String targetUserId;
  final String targetName;

  const FamilyMemberRemoved({
    required this.actorUserId,
    required this.familyId,
    required this.targetUserId,
    required this.targetName,
  });

  @override
  List<Object?> get props => [actorUserId, familyId, targetUserId, targetName];
}

final class FamilyJoinByCodeSubmitted extends FamilyEvent {
  final String userId;
  final String userName;
  final String inviteCode;

  const FamilyJoinByCodeSubmitted({
    required this.userId,
    required this.userName,
    required this.inviteCode,
  });

  @override
  List<Object?> get props => [userId, userName, inviteCode];
}

final class FamilyLeaveConfirmed extends FamilyEvent {
  final String userId;
  final String familyId;

  const FamilyLeaveConfirmed({required this.userId, required this.familyId});

  @override
  List<Object?> get props => [userId, familyId];
}

final class ShoppingItemAdded extends FamilyEvent {
  final String familyId;
  final String userName;
  final String title;
  final String quantityLabel;
  final int estimatedPriceMinor;

  const ShoppingItemAdded({
    required this.familyId,
    required this.userName,
    required this.title,
    required this.quantityLabel,
    required this.estimatedPriceMinor,
  });

  @override
  List<Object?> get props => [
    familyId,
    userName,
    title,
    quantityLabel,
    estimatedPriceMinor,
  ];
}

final class ShoppingItemToggled extends FamilyEvent {
  final String familyId;
  final String itemId;
  final bool isPurchased;

  const ShoppingItemToggled({
    required this.familyId,
    required this.itemId,
    required this.isPurchased,
  });

  @override
  List<Object?> get props => [familyId, itemId, isPurchased];
}

final class SharedBillSplitCreated extends FamilyEvent {
  final CreateSharedBillSplitParams params;
  const SharedBillSplitCreated(this.params);

  @override
  List<Object?> get props => [params];
}

final class DebtSettlementRecorded extends FamilyEvent {
  final RecordDebtSettlementParams params;
  const DebtSettlementRecorded(this.params);

  @override
  List<Object?> get props => [params];
}

final class FamilyState extends Equatable {
  final bool isLoading;
  final bool isSubmitting;
  final bool isPreviewingInvite;
  final List<FamilyEntity> families;
  final String? selectedFamilyId;
  final List<ShoppingItemEntity> shoppingItems;
  final List<SharedBillSplitEntity> sharedBills;
  final List<DebtSettlementEntity> settlements;
  final String? latestInviteCode;
  final FamilyPendingInviteEntity? previewedInvite;
  final Failure? failure;
  final String? message;

  const FamilyState({
    this.isLoading = false,
    this.isSubmitting = false,
    this.isPreviewingInvite = false,
    this.families = const [],
    this.selectedFamilyId,
    this.shoppingItems = const [],
    this.sharedBills = const [],
    this.settlements = const [],
    this.latestInviteCode,
    this.previewedInvite,
    this.failure,
    this.message,
  });

  FamilyEntity? get activeFamily {
    if (families.isEmpty) return null;
    if (selectedFamilyId != null) {
      final found = families.where((f) => f.id == selectedFamilyId).firstOrNull;
      if (found != null) return found;
    }
    return families.first;
  }

  SharedLedgerSummary get sharedLedger {
    final fam = activeFamily;
    if (fam == null) return const SharedLedgerSummary();
    return DebtSimplifier.summarize(
      familyId: fam.id,
      members: fam.members,
      bills: sharedBills,
      settlements: settlements,
    );
  }

  FamilyState copyWith({
    bool? isLoading,
    bool? isSubmitting,
    bool? isPreviewingInvite,
    List<FamilyEntity>? families,
    String? selectedFamilyId,
    bool clearSelectedFamily = false,
    List<ShoppingItemEntity>? shoppingItems,
    List<SharedBillSplitEntity>? sharedBills,
    List<DebtSettlementEntity>? settlements,
    String? latestInviteCode,
    bool clearLatestInviteCode = false,
    FamilyPendingInviteEntity? previewedInvite,
    bool clearPreviewedInvite = false,
    Failure? failure,
    bool clearFailure = false,
    String? message,
    bool clearMessage = false,
  }) {
    return FamilyState(
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isPreviewingInvite: isPreviewingInvite ?? this.isPreviewingInvite,
      families: families != null ? List.unmodifiable(families) : this.families,
      selectedFamilyId: clearSelectedFamily
          ? null
          : (selectedFamilyId ?? this.selectedFamilyId),
      shoppingItems: shoppingItems != null
          ? List.unmodifiable(shoppingItems)
          : this.shoppingItems,
      sharedBills: sharedBills != null
          ? List.unmodifiable(sharedBills)
          : this.sharedBills,
      settlements: settlements != null
          ? List.unmodifiable(settlements)
          : this.settlements,
      latestInviteCode: clearLatestInviteCode
          ? null
          : (latestInviteCode ?? this.latestInviteCode),
      previewedInvite: clearPreviewedInvite
          ? null
          : (previewedInvite ?? this.previewedInvite),
      failure: clearFailure ? null : (failure ?? this.failure),
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    isSubmitting,
    isPreviewingInvite,
    families,
    selectedFamilyId,
    shoppingItems,
    sharedBills,
    settlements,
    latestInviteCode,
    previewedInvite,
    failure,
    message,
  ];
}

class FamilyBloc extends Bloc<FamilyEvent, FamilyState> {
  final FamilyRepository _repository;
  final CreateFamilyUseCase _createFamily;
  final JoinFamilyByCodeUseCase _joinFamily;
  final CreateSharedBillSplitUseCase _createSharedBillSplit;
  final RecordDebtSettlementUseCase _recordDebtSettlement;

  FamilyBloc({
    required FamilyRepository repository,
    required CreateFamilyUseCase createFamily,
    required JoinFamilyByCodeUseCase joinFamily,
    CreateSharedBillSplitUseCase? createSharedBillSplit,
    RecordDebtSettlementUseCase? recordDebtSettlement,
  }) : _repository = repository,
       _createFamily = createFamily,
       _joinFamily = joinFamily,
       _createSharedBillSplit =
           createSharedBillSplit ?? CreateSharedBillSplitUseCase(repository),
       _recordDebtSettlement =
           recordDebtSettlement ?? RecordDebtSettlementUseCase(repository),
       super(const FamilyState()) {
    on<FamilySubscriptionRequested>(
      _onSubscriptionRequested,
      transformer: restartable(),
    );
    on<FamilyShoppingWatchRequested>(
      _onShoppingWatchRequested,
      transformer: restartable(),
    );
    on<FamilyCreateSubmitted>(_onCreateFamily, transformer: sequential());
    on<FamilyInviteGenerated>(_onGenerateInvite, transformer: sequential());
    on<FamilyInvitePreviewRequested>(
      _onPreviewInvite,
      transformer: restartable(),
    );
    on<FamilyInvitePreviewCleared>(_onClearPreviewInvite);
    on<FamilyInviteRevokeRequested>(_onRevokeInvite, transformer: sequential());
    on<FamilyMemberRoleUpdated>(_onUpdateMemberRole, transformer: sequential());
    on<FamilyMemberRemoved>(_onRemoveMember, transformer: sequential());
    on<FamilyJoinByCodeSubmitted>(_onJoinFamily, transformer: sequential());
    on<FamilyLeaveConfirmed>(_onLeaveFamily, transformer: sequential());
    on<ShoppingItemAdded>(_onAddShoppingItem, transformer: sequential());
    on<ShoppingItemToggled>(_onToggleShoppingItem, transformer: sequential());
    on<SharedBillSplitCreated>(_onCreateSharedBill, transformer: sequential());
    on<DebtSettlementRecorded>(_onRecordSettlement, transformer: sequential());
  }

  Future<void> _onSubscriptionRequested(
    FamilySubscriptionRequested event,
    Emitter<FamilyState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));
    await emit.forEach<Result<List<FamilyEntity>>>(
      _repository.watchMyFamilies(event.userId),
      onData: (res) {
        return res.fold(
          (failure) => state.copyWith(
            isLoading: false,
            failure: failure,
            clearMessage: true,
          ),
          (list) {
            final validIds = list.map((f) => f.id).toSet();
            final currentSelected =
                (state.selectedFamilyId != null &&
                    validIds.contains(state.selectedFamilyId))
                ? state.selectedFamilyId
                : null;
            final preferred =
                (event.preferredFamilyId != null &&
                    validIds.contains(event.preferredFamilyId))
                ? event.preferredFamilyId
                : null;
            final chosenId =
                currentSelected ??
                preferred ??
                (list.isNotEmpty ? list.first.id : null);
            if (chosenId != null && chosenId != state.selectedFamilyId) {
              add(FamilyShoppingWatchRequested(chosenId));
            }
            return state.copyWith(
              isLoading: false,
              families: list,
              selectedFamilyId: chosenId,
              clearSelectedFamily: list.isEmpty,
              shoppingItems: list.isEmpty ? const [] : state.shoppingItems,
              sharedBills: list.isEmpty ? const [] : state.sharedBills,
              settlements: list.isEmpty ? const [] : state.settlements,
              clearFailure: true,
              clearMessage: true,
            );
          },
        );
      },
    );
  }

  Future<void> _onShoppingWatchRequested(
    FamilyShoppingWatchRequested event,
    Emitter<FamilyState> emit,
  ) async {
    emit(state.copyWith(selectedFamilyId: event.familyId));
    final combined =
        StreamCombiner.combine3<
          Result<List<ShoppingItemEntity>>,
          Result<List<SharedBillSplitEntity>>,
          Result<List<DebtSettlementEntity>>,
          FamilyState
        >(
          _repository.watchShoppingItems(event.familyId),
          _repository.watchSharedBills(event.familyId),
          _repository.watchSettlements(event.familyId),
          (shopRes, billsRes, settleRes) {
            if (shopRes is Err<List<ShoppingItemEntity>>) {
              return state.copyWith(failure: shopRes.failure);
            }
            if (billsRes is Err<List<SharedBillSplitEntity>>) {
              return state.copyWith(failure: billsRes.failure);
            }
            if (settleRes is Err<List<DebtSettlementEntity>>) {
              return state.copyWith(failure: settleRes.failure);
            }
            return state.copyWith(
              shoppingItems:
                  (shopRes as Success<List<ShoppingItemEntity>>).value,
              sharedBills:
                  (billsRes as Success<List<SharedBillSplitEntity>>).value,
              settlements:
                  (settleRes as Success<List<DebtSettlementEntity>>).value,
              clearFailure: true,
            );
          },
        );

    await emit.forEach<FamilyState>(combined, onData: (next) => next);
  }

  Future<void> _onCreateFamily(
    FamilyCreateSubmitted event,
    Emitter<FamilyState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        clearFailure: true,
        clearMessage: true,
      ),
    );
    final res = await _createFamily(
      CreateFamilyParams(
        userId: event.userId,
        userName: event.userName,
        familyName: event.familyName,
        spaceType: event.spaceType,
      ),
    );
    res.fold((f) => emit(state.copyWith(isSubmitting: false, failure: f)), (
      fam,
    ) {
      add(FamilyShoppingWatchRequested(fam.id));
      emit(
        state.copyWith(
          isSubmitting: false,
          selectedFamilyId: fam.id,
          message: 'Đã khởi tạo ${fam.spaceType.displayLabel} "${fam.name}".',
        ),
      );
    });
  }

  Future<void> _onGenerateInvite(
    FamilyInviteGenerated event,
    Emitter<FamilyState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        clearFailure: true,
        clearMessage: true,
      ),
    );
    final res = await _repository.createInviteCode(
      userId: event.userId,
      familyId: event.familyId,
      familyName: event.familyName,
      spaceType: event.spaceType,
      invitedByName: event.invitedByName,
      inviteeName: event.inviteeName,
      inviteeContact: event.inviteeContact,
    );
    res.fold((f) => emit(state.copyWith(isSubmitting: false, failure: f)), (
      code,
    ) {
      final targetLabel =
          (event.inviteeName != null && event.inviteeName!.trim().isNotEmpty)
          ? 'cho ${event.inviteeName!.trim()} ($code)'
          : code;
      emit(
        state.copyWith(
          isSubmitting: false,
          latestInviteCode: code,
          message: 'Đã tạo lời mời tham gia nhóm $targetLabel',
        ),
      );
    });
  }

  Future<void> _onPreviewInvite(
    FamilyInvitePreviewRequested event,
    Emitter<FamilyState> emit,
  ) async {
    emit(
      state.copyWith(
        isPreviewingInvite: true,
        clearPreviewedInvite: true,
        clearFailure: true,
      ),
    );
    final res = await _repository.previewInviteCode(
      inviteCode: event.inviteCode,
    );
    res.fold(
      (f) => emit(state.copyWith(isPreviewingInvite: false, failure: f)),
      (preview) => emit(
        state.copyWith(isPreviewingInvite: false, previewedInvite: preview),
      ),
    );
  }

  void _onClearPreviewInvite(
    FamilyInvitePreviewCleared event,
    Emitter<FamilyState> emit,
  ) {
    emit(state.copyWith(clearPreviewedInvite: true, clearFailure: true));
  }

  Future<void> _onRevokeInvite(
    FamilyInviteRevokeRequested event,
    Emitter<FamilyState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        clearFailure: true,
        clearMessage: true,
      ),
    );
    final res = await _repository.revokeInviteCode(
      actorUserId: event.actorUserId,
      familyId: event.familyId,
      inviteCode: event.inviteCode,
    );
    res.fold(
      (f) => emit(state.copyWith(isSubmitting: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSubmitting: false,
          clearLatestInviteCode: state.latestInviteCode == event.inviteCode,
          message: 'Đã thu hồi lời mời ${event.inviteCode}.',
        ),
      ),
    );
  }

  Future<void> _onUpdateMemberRole(
    FamilyMemberRoleUpdated event,
    Emitter<FamilyState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        clearFailure: true,
        clearMessage: true,
      ),
    );
    final res = await _repository.updateMemberRole(
      actorUserId: event.actorUserId,
      familyId: event.familyId,
      targetUserId: event.targetUserId,
      newRole: event.newRole,
    );
    res.fold(
      (f) => emit(state.copyWith(isSubmitting: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSubmitting: false,
          message:
              'Đã cập nhật quyền của ${event.targetName} thành ${event.newRole.displayLabel}.',
        ),
      ),
    );
  }

  Future<void> _onRemoveMember(
    FamilyMemberRemoved event,
    Emitter<FamilyState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        clearFailure: true,
        clearMessage: true,
      ),
    );
    final res = await _repository.removeMember(
      actorUserId: event.actorUserId,
      familyId: event.familyId,
      targetUserId: event.targetUserId,
    );
    res.fold(
      (f) => emit(state.copyWith(isSubmitting: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSubmitting: false,
          message: 'Đã xóa ${event.targetName} khỏi nhóm.',
        ),
      ),
    );
  }

  Future<void> _onJoinFamily(
    FamilyJoinByCodeSubmitted event,
    Emitter<FamilyState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        clearFailure: true,
        clearMessage: true,
      ),
    );
    final res = await _joinFamily(
      JoinFamilyParams(
        userId: event.userId,
        userName: event.userName,
        inviteCode: event.inviteCode,
      ),
    );
    res.fold((f) => emit(state.copyWith(isSubmitting: false, failure: f)), (
      fam,
    ) {
      add(FamilyShoppingWatchRequested(fam.id));
      emit(
        state.copyWith(
          isSubmitting: false,
          clearPreviewedInvite: true,
          selectedFamilyId: fam.id,
          message: 'Đã tham gia "${fam.name}".',
        ),
      );
    });
  }

  Future<void> _onLeaveFamily(
    FamilyLeaveConfirmed event,
    Emitter<FamilyState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        clearFailure: true,
        clearMessage: true,
      ),
    );
    final res = await _repository.leaveFamily(
      userId: event.userId,
      familyId: event.familyId,
    );
    res.fold(
      (f) => emit(state.copyWith(isSubmitting: false, failure: f)),
      (_) => emit(
        state.copyWith(
          isSubmitting: false,
          clearSelectedFamily: true,
          shoppingItems: const [],
          sharedBills: const [],
          settlements: const [],
          message: 'Đã rời nhóm và thu hồi quyền chia sẻ.',
        ),
      ),
    );
  }

  Future<void> _onAddShoppingItem(
    ShoppingItemAdded event,
    Emitter<FamilyState> emit,
  ) async {
    if (event.title.trim().isEmpty) {
      emit(
        state.copyWith(
          failure: const ValidationFailure(
            message: 'Vui lòng nhập tên món cần mua.',
          ),
        ),
      );
      return;
    }
    final res = await _repository.addShoppingItem(
      familyId: event.familyId,
      userName: event.userName,
      title: event.title.trim(),
      quantityLabel: event.quantityLabel.trim().isEmpty
          ? '1'
          : event.quantityLabel.trim(),
      estimatedPriceMinor: event.estimatedPriceMinor < 0
          ? 0
          : event.estimatedPriceMinor,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(message: 'Đã thêm vào danh sách mua sắm.')),
    );
  }

  Future<void> _onToggleShoppingItem(
    ShoppingItemToggled event,
    Emitter<FamilyState> emit,
  ) async {
    final res = await _repository.toggleShoppingItem(
      familyId: event.familyId,
      itemId: event.itemId,
      isPurchased: event.isPurchased,
    );
    res.fold((f) => emit(state.copyWith(failure: f)), (_) {});
  }

  Future<void> _onCreateSharedBill(
    SharedBillSplitCreated event,
    Emitter<FamilyState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        clearFailure: true,
        clearMessage: true,
      ),
    );
    final res = await _createSharedBillSplit(event.params);
    res.fold(
      (f) => emit(state.copyWith(isSubmitting: false, failure: f)),
      (bill) => emit(
        state.copyWith(
          isSubmitting: false,
          message:
              'Đã chia khoản "${bill.title}" (${bill.splitMethod.displayLabel}).',
        ),
      ),
    );
  }

  Future<void> _onRecordSettlement(
    DebtSettlementRecorded event,
    Emitter<FamilyState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        clearFailure: true,
        clearMessage: true,
      ),
    );
    final res = await _recordDebtSettlement(event.params);
    res.fold(
      (f) => emit(state.copyWith(isSubmitting: false, failure: f)),
      (st) => emit(
        state.copyWith(
          isSubmitting: false,
          message:
              'Đã ghi nhận tất toán ${st.fromUserName} → ${st.toUserName} (${st.paymentCode}).',
        ),
      ),
    );
  }
}
