import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../entities/family_entities.dart';
import '../repositories/family_repository.dart';

final class CreateFamilyParams {
  final String userId;
  final String userName;
  final String familyName;
  final CollaborationSpaceType spaceType;

  const CreateFamilyParams({
    required this.userId,
    required this.userName,
    required this.familyName,
    this.spaceType = CollaborationSpaceType.family,
  });
}

class CreateFamilyUseCase implements UseCase<FamilyEntity, CreateFamilyParams> {
  final FamilyRepository _repository;
  const CreateFamilyUseCase(this._repository);

  @override
  Future<Result<FamilyEntity>> call(CreateFamilyParams params) async {
    final name = params.familyName.trim();
    if (name.length < 2) {
      return const Err(
        ValidationFailure(
          message: 'Tên nhóm / hộ gia đình phải có ít nhất 2 ký tự.',
        ),
      );
    }
    return _repository.createFamily(
      userId: params.userId,
      userName: params.userName,
      familyName: name,
      spaceType: params.spaceType,
    );
  }
}

final class JoinFamilyParams {
  final String userId;
  final String userName;
  final String inviteCode;
  final String? userEmail;
  final String? userPhone;

  const JoinFamilyParams({
    required this.userId,
    required this.userName,
    required this.inviteCode,
    this.userEmail,
    this.userPhone,
  });
}

class JoinFamilyByCodeUseCase
    implements UseCase<FamilyEntity, JoinFamilyParams> {
  final FamilyRepository _repository;
  const JoinFamilyByCodeUseCase(this._repository);

  @override
  Future<Result<FamilyEntity>> call(JoinFamilyParams params) async {
    final code = FamilyInviteCodeExtractor.extractCode(params.inviteCode);
    if (code.length < 4) {
      return const Err(
        ValidationFailure(
          message: 'Vui lòng nhập mã mời hợp lệ (ví dụ: FAM-8K2P9Q).',
        ),
      );
    }
    return _repository.joinFamilyByInvite(
      userId: params.userId,
      userName: params.userName,
      inviteCode: code,
      userEmail: params.userEmail,
      userPhone: params.userPhone,
    );
  }
}

final class CreateSharedBillSplitParams {
  final String familyId;
  final String title;
  final SharedExpenseTopic topic;
  final String paidByUserId;
  final String paidByName;
  final int totalAmountMinor;
  final SplitMethod splitMethod;
  final List<String> participantIds;
  final Map<String, String> participantNames;

  /// Raw inputs keyed by `userId`:
  /// - `equal`: ignored (computed automatically)
  /// - `percentage`: integer percentages summing to 100
  /// - `shares`: integer weights > 0 (e.g. 2 parts vs 1 part)
  /// - `exact`: exact VND amounts summing to `totalAmountMinor`
  final Map<String, int> rawInputValuesByUserId;
  final String? choreOrTaskNote;

  const CreateSharedBillSplitParams({
    required this.familyId,
    required this.title,
    required this.topic,
    required this.paidByUserId,
    required this.paidByName,
    required this.totalAmountMinor,
    required this.splitMethod,
    required this.participantIds,
    required this.participantNames,
    this.rawInputValuesByUserId = const {},
    this.choreOrTaskNote,
  });
}

class CreateSharedBillSplitUseCase
    implements UseCase<SharedBillSplitEntity, CreateSharedBillSplitParams> {
  final FamilyRepository _repository;
  const CreateSharedBillSplitUseCase(this._repository);

  @override
  Future<Result<SharedBillSplitEntity>> call(
    CreateSharedBillSplitParams params,
  ) async {
    final cleanTitle = params.title.trim();
    if (cleanTitle.length < 2) {
      return const Err(
        ValidationFailure(
          message:
              'Vui lòng nhập nội dung khoản chi chung (tối thiểu 2 ký tự).',
        ),
      );
    }
    if (params.totalAmountMinor <= 0 ||
        params.totalAmountMinor > VndAmount.maxAllowedMinor) {
      return const Err(
        ValidationFailure(
          message: 'Tổng tiền chia phải là số nguyên dương (VND).',
        ),
      );
    }
    final uniqueParticipants = params.participantIds.toSet().toList();
    if (uniqueParticipants.isEmpty) {
      return const Err(
        ValidationFailure(
          message: 'Phải có ít nhất 1 thành viên tham gia chia khoản này.',
        ),
      );
    }

    late final Map<String, int> resolvedShares;
    switch (params.splitMethod) {
      case SplitMethod.equal:
        resolvedShares = SplitBillCalculator.computeEqualSplit(
          totalAmountMinor: params.totalAmountMinor,
          participantIds: uniqueParticipants,
          payerUserId: params.paidByUserId,
        );
      case SplitMethod.percentage:
        final filtered = <String, int>{
          for (final uid in uniqueParticipants)
            uid: params.rawInputValuesByUserId[uid] ?? 0,
        };
        final pctSum = filtered.values.fold<int>(0, (s, v) => s + v);
        if (pctSum != 100 || filtered.values.any((v) => v < 0)) {
          return Err(
            ValidationFailure(
              message:
                  'Tổng tỷ lệ phần trăm phải bằng đúng 100% (hiện tại: $pctSum%).',
            ),
          );
        }
        resolvedShares = SplitBillCalculator.computeWeightedSplit(
          totalAmountMinor: params.totalAmountMinor,
          weightsByUserId: filtered,
        );
      case SplitMethod.shares:
        final filtered = <String, int>{
          for (final uid in uniqueParticipants)
            uid: params.rawInputValuesByUserId[uid] ?? 0,
        };
        final weightSum = filtered.values.fold<int>(0, (s, v) => s + v);
        if (weightSum <= 0 || filtered.values.any((v) => v < 0)) {
          return const Err(
            ValidationFailure(
              message: 'Tổng số phần chia phải lớn hơn 0 và không được âm.',
            ),
          );
        }
        resolvedShares = SplitBillCalculator.computeWeightedSplit(
          totalAmountMinor: params.totalAmountMinor,
          weightsByUserId: filtered,
        );
      case SplitMethod.exact:
        final exactMap = <String, int>{};
        var exactSum = 0;
        for (final uid in uniqueParticipants) {
          final v = params.rawInputValuesByUserId[uid] ?? 0;
          if (v < 0) {
            return const Err(
              ValidationFailure(message: 'Số tiền từng người không được âm.'),
            );
          }
          if (v > 0) {
            exactMap[uid] = v;
            exactSum += v;
          }
        }
        if (exactSum != params.totalAmountMinor) {
          return Err(
            ValidationFailure(
              message:
                  'Tổng tiền từng người (${VndAmount.format(exactSum)}) phải bằng đúng hóa đơn (${VndAmount.format(params.totalAmountMinor)}).',
            ),
          );
        }
        resolvedShares = Map.unmodifiable(exactMap);
    }

    return _repository.createSharedBillSplit(
      familyId: params.familyId,
      title: cleanTitle,
      topic: params.topic,
      paidByUserId: params.paidByUserId,
      paidByName: params.paidByName,
      totalAmountMinor: params.totalAmountMinor,
      splitMethod: params.splitMethod,
      sharesByUserId: resolvedShares,
      participantNames: params.participantNames,
      choreOrTaskNote: params.choreOrTaskNote?.trim(),
    );
  }
}

final class RecordDebtSettlementParams {
  final String familyId;
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String toUserName;
  final int amountMinor;
  final String? paymentCode;
  final bool isPartial;
  final String? settlementRequestId;
  final String? note;

  const RecordDebtSettlementParams({
    required this.familyId,
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    required this.amountMinor,
    this.paymentCode,
    this.isPartial = false,
    this.settlementRequestId,
    this.note,
  });
}

class RecordDebtSettlementUseCase
    implements UseCase<DebtSettlementEntity, RecordDebtSettlementParams> {
  final FamilyRepository _repository;
  const RecordDebtSettlementUseCase(this._repository);

  @override
  Future<Result<DebtSettlementEntity>> call(
    RecordDebtSettlementParams params,
  ) async {
    if (params.fromUserId == params.toUserId) {
      return const Err(
        ValidationFailure(
          message: 'Người trả nợ và người nhận không được là cùng một người.',
        ),
      );
    }
    if (params.amountMinor <= 0 ||
        params.amountMinor > VndAmount.maxAllowedMinor) {
      return const Err(
        ValidationFailure(
          message: 'Số tiền tất toán phải là số nguyên dương (VND).',
        ),
      );
    }
    final resolvedCode =
        (params.paymentCode != null && params.paymentCode!.trim().isNotEmpty)
        ? params.paymentCode!.trim()
        : BankNotificationParser.buildSePayTransferCode(
            scopePrefix: 'SPLIT',
            seed:
                '${params.familyId}:${params.fromUserId}:${params.toUserId}:${params.amountMinor}',
          );

    return _repository.recordDebtSettlement(
      familyId: params.familyId,
      fromUserId: params.fromUserId,
      fromUserName: params.fromUserName,
      toUserId: params.toUserId,
      toUserName: params.toUserName,
      amountMinor: params.amountMinor,
      paymentCode: resolvedCode,
      isPartial: params.isPartial,
      settlementRequestId: params.settlementRequestId,
      note: params.note?.trim(),
    );
  }
}

final class RequestDebtSettlementParams {
  final String familyId;
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String toUserName;
  final int amountMinor;
  final String? paymentCode;
  final bool isPartial;
  final String? note;

  const RequestDebtSettlementParams({
    required this.familyId,
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    required this.amountMinor,
    this.paymentCode,
    this.isPartial = false,
    this.note,
  });
}

class RequestDebtSettlementUseCase
    implements UseCase<SettlementRequestEntity, RequestDebtSettlementParams> {
  final FamilyRepository _repository;
  const RequestDebtSettlementUseCase(this._repository);

  @override
  Future<Result<SettlementRequestEntity>> call(
    RequestDebtSettlementParams params,
  ) async {
    if (params.fromUserId == params.toUserId) {
      return const Err(
        ValidationFailure(
          message: 'Người trả nợ và người nhận không được là cùng một người.',
        ),
      );
    }
    if (params.amountMinor <= 0 ||
        params.amountMinor > VndAmount.maxAllowedMinor) {
      return const Err(
        ValidationFailure(
          message: 'Số tiền tất toán phải là số nguyên dương (VND).',
        ),
      );
    }
    final resolvedCode =
        (params.paymentCode != null && params.paymentCode!.trim().isNotEmpty)
        ? params.paymentCode!.trim()
        : BankNotificationParser.buildSePayTransferCode(
            scopePrefix: 'SPLIT',
            seed:
                '${params.familyId}:${params.fromUserId}:${params.toUserId}:${params.amountMinor}',
          );

    return _repository.requestDebtSettlement(
      familyId: params.familyId,
      fromUserId: params.fromUserId,
      fromUserName: params.fromUserName,
      toUserId: params.toUserId,
      toUserName: params.toUserName,
      amountMinor: params.amountMinor,
      paymentCode: resolvedCode,
      isPartial: params.isPartial,
      note: params.note?.trim(),
    );
  }
}

final class ConfirmSettlementRequestParams {
  final String familyId;
  final String requestId;
  final String actorUserId;
  final bool approve;
  final String? disputeReason;

  const ConfirmSettlementRequestParams({
    required this.familyId,
    required this.requestId,
    required this.actorUserId,
    required this.approve,
    this.disputeReason,
  });
}

class ConfirmSettlementRequestUseCase
    implements UseCase<DebtSettlementEntity?, ConfirmSettlementRequestParams> {
  final FamilyRepository _repository;
  const ConfirmSettlementRequestUseCase(this._repository);

  @override
  Future<Result<DebtSettlementEntity?>> call(
    ConfirmSettlementRequestParams params,
  ) {
    if (params.requestId.trim().isEmpty || params.actorUserId.trim().isEmpty) {
      return Future.value(
        const Err(
          ValidationFailure(message: 'Thiếu mã yêu cầu tất toán hợp lệ.'),
        ),
      );
    }
    return _repository.confirmSettlementRequest(
      familyId: params.familyId,
      requestId: params.requestId.trim(),
      actorUserId: params.actorUserId.trim(),
      approve: params.approve,
      disputeReason: params.disputeReason?.trim(),
    );
  }
}

final class ReverseDebtSettlementParams {
  final String familyId;
  final String settlementId;
  final String actorUserId;
  final String? reason;

  const ReverseDebtSettlementParams({
    required this.familyId,
    required this.settlementId,
    required this.actorUserId,
    this.reason,
  });
}

class ReverseDebtSettlementUseCase
    implements UseCase<DebtSettlementEntity, ReverseDebtSettlementParams> {
  final FamilyRepository _repository;
  const ReverseDebtSettlementUseCase(this._repository);

  @override
  Future<Result<DebtSettlementEntity>> call(
    ReverseDebtSettlementParams params,
  ) {
    if (params.settlementId.trim().isEmpty ||
        params.actorUserId.trim().isEmpty) {
      return Future.value(
        const Err(
          ValidationFailure(message: 'Thiếu mã khoản tất toán cần hoàn tác.'),
        ),
      );
    }
    return _repository.reverseDebtSettlement(
      familyId: params.familyId,
      settlementId: params.settlementId.trim(),
      actorUserId: params.actorUserId.trim(),
      reason: params.reason?.trim(),
    );
  }
}
