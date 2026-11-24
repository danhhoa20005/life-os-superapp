import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../features/authentication/domain/entities/user_entity.dart';
import '../../features/calendar/domain/entities/calendar_entities.dart';
import '../../features/calendar/domain/repositories/calendar_repository.dart';
import '../../features/calendar/presentation/bloc/calendar_bloc.dart';
import '../../features/daily_life/domain/entities/daily_life_entities.dart';
import '../../features/daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../features/family/domain/entities/family_entities.dart';
import '../../features/family/domain/usecases/family_usecases.dart';
import '../../features/family/presentation/bloc/family_bloc.dart';
import '../../features/tasks/domain/entities/task_entities.dart';
import '../../features/tasks/domain/repositories/task_repository.dart';
import '../../features/tasks/presentation/bloc/task_bloc.dart';
import '../../features/transactions/presentation/bloc/transaction_bloc.dart';
import '../../features/transactions/presentation/bloc/transaction_event.dart';
import '../di/dependency_injection.dart';
import '../widgets/lifeos_top_toast.dart';
import 'smart_omni_intent_parser.dart';
import 'user_behavior_prefs.dart';
import 'vnd_amount.dart';

/// Unified cross-domain action dispatcher with RFM habit learning and 1-Tap Undo
/// (inspired by Revolut, Todoist & MoMo ergonomics).
abstract final class OmniActionExecutor {
  static const Uuid _uuid = Uuid();

  static Future<bool> executeDraft({
    required BuildContext toastContext,
    required OmniActionDraft draft,
    required UserEntity user,
    required String walletId,
    TransactionActionBloc? txActionBloc,
    CalendarBloc? calBloc,
    TaskBloc? taskBloc,
    FamilyBloc? familyBloc,
    DailyLifeBloc? dailyBloc,
    bool showSuccessToast = true,
  }) async {
    switch (draft.kind) {
      case OmniActionKind.transaction:
        if (txActionBloc == null || draft.amountMinor <= 0) return false;
        final opId = _uuid.v4();
        await UserBehaviorPrefs.rememberWallet(walletId);
        await UserBehaviorPrefs.recordHabitExecution(
          label:
              '${draft.title} ${(draft.amountMinor / 1000).round()}k',
          commandText:
              '${draft.title} ${(draft.amountMinor / 1000).round()}k',
          categoryName: draft.categoryName,
          amountMinor: draft.amountMinor,
        );
        txActionBloc.add(
          TransactionCreateSubmitted(
            operationId: opId,
            userId: user.id,
            walletId: walletId,
            categoryId: draft.categoryId,
            categoryName: draft.categoryName,
            kind: draft.transactionKind,
            amountMinor: draft.amountMinor,
            merchant: draft.title,
            note: 'Ghi thông minh (${draft.originLabel})',
            occurredAt: DateTime.now(),
          ),
        );
        if (showSuccessToast && toastContext.mounted) {
          LifeOsTopToast.show(
            toastContext,
            'Đã lưu: ${draft.title} (${VndAmount.format(draft.amountMinor)})',
            actionLabel: 'Hoàn tác',
            onAction: () {
              txActionBloc.add(
                TransactionReverseRequested(
                  userId: user.id,
                  transactionId: opId,
                  reason: 'Hoàn tác thao tác ghi nhanh',
                ),
              );
              if (toastContext.mounted) {
                LifeOsTopToast.show(
                  toastContext,
                  'Đã hoàn tác khoản "${draft.title}".',
                  kind: LifeOsToastKind.info,
                );
              }
            },
          );
        }
        return true;

      case OmniActionKind.groupSplit:
        if (familyBloc == null || draft.amountMinor <= 0) return false;
        var targetFamily = familyBloc.state.activeFamily;
        if (targetFamily == null) {
          final createRes = await sl<CreateFamilyUseCase>()(
            CreateFamilyParams(
              userId: user.id,
              userName: user.fullName,
              familyName: 'Nhóm Chia Tiền Nhanh',
              spaceType: CollaborationSpaceType.group,
            ),
          );
          targetFamily = createRes.fold((_) => null, (fam) => fam);
        }
        final famId = targetFamily?.id ?? user.activeFamilyId;
        if (famId == null || famId.isEmpty) return false;

        final participantIds = <String>[user.id];
        final participantNames = <String, String>{user.id: user.fullName};
        final existingOthers =
            (targetFamily?.members ?? const <FamilyMemberInfo>[])
                .where((m) => m.userId != user.id)
                .toList();
        for (var i = 1; i < draft.participantCount; i++) {
          if (i - 1 < existingOthers.length) {
            final m = existingOthers[i - 1];
            participantIds.add(m.userId);
            participantNames[m.userId] = m.fullName;
          } else {
            final guestId = 'guest_member_$i';
            participantIds.add(guestId);
            participantNames[guestId] = 'Thành viên ${i + 1}';
          }
        }

        final splitParams = CreateSharedBillSplitParams(
          familyId: famId,
          title: draft.title,
          topic: SharedExpenseTopic.dining,
          paidByUserId: user.id,
          paidByName: user.fullName,
          totalAmountMinor: draft.amountMinor,
          splitMethod: SplitMethod.equal,
          participantIds: participantIds,
          participantNames: participantNames,
          rawInputValuesByUserId: const <String, int>{},
          choreOrTaskNote: 'Chia tự động (${draft.originLabel})',
        );
        if (!familyBloc.isClosed) {
          familyBloc.add(SharedBillSplitCreated(splitParams));
        } else {
          await sl<CreateSharedBillSplitUseCase>()(splitParams);
        }
        await UserBehaviorPrefs.recordHabitExecution(
          label: 'Chia ${draft.participantCount} người',
          commandText:
              '${draft.title} ${(draft.amountMinor / 1000).round()}k chia ${draft.participantCount} người',
          amountMinor: draft.amountMinor,
        );
        if (showSuccessToast && toastContext.mounted) {
          LifeOsTopToast.show(
            toastContext,
            'Đã chia "${draft.title}" (${VndAmount.format(draft.perPersonShareMinor)}/người)',
          );
        }
        return true;

      case OmniActionKind.calendarEvent:
        if (calBloc == null) return false;
        final now = DateTime.now();
        final startsAt =
            draft.scheduledAt ??
            DateTime(now.year, now.month, now.day + 1, 9, 0);
        final endsAt = startsAt.add(Duration(minutes: draft.durationMinutes));
        calBloc.add(
          CalendarEventCreated(
            CreateCalendarEventParams(
              userId: user.id,
              userName: user.fullName,
              familyId: user.activeFamilyId,
              visibility: CalendarEventVisibility.privateEvent,
              title: draft.title,
              location: draft.location,
              startsAt: startsAt,
              endsAt: endsAt,
            ),
          ),
        );
        await UserBehaviorPrefs.recordHabitExecution(
          label: draft.title,
          commandText: 'Lịch ${draft.title}',
        );
        if (showSuccessToast && toastContext.mounted) {
          LifeOsTopToast.show(
            toastContext,
            'Đã thêm lịch hẹn: "${draft.title}"',
          );
        }
        return true;

      case OmniActionKind.task:
        if (taskBloc == null) return false;
        final now = DateTime.now();
        final dueAt =
            draft.scheduledAt ?? DateTime(now.year, now.month, now.day, 20, 0);
        taskBloc.add(
          TaskCreateSubmitted(
            CreateTaskParams(
              createdBy: user.id,
              creatorName: user.fullName,
              familyId: user.activeFamilyId,
              assigneeId: user.id,
              assigneeName: user.fullName,
              title: draft.title,
              dueAt: dueAt,
              priority: draft.taskPriority,
              recurrence: TaskRecurrence.none,
            ),
          ),
        );
        await UserBehaviorPrefs.recordHabitExecution(
          label: draft.title,
          commandText: 'Nhắc ${draft.title}',
        );
        if (showSuccessToast && toastContext.mounted) {
          LifeOsTopToast.show(
            toastContext,
            'Đã thêm việc cần làm: "${draft.title}"',
          );
        }
        return true;

      case OmniActionKind.grocery:
        if (dailyBloc == null) return false;
        dailyBloc.add(
          GroceryItemAdded(
            userId: user.id,
            name: draft.title,
            quantityLabel: draft.quantityLabel,
            aisle: GroceryAisle.produce,
            estimatedMinor: draft.amountMinor,
          ),
        );
        await UserBehaviorPrefs.recordHabitExecution(
          label: 'Mua ${draft.title}',
          commandText: 'Đi chợ mua ${draft.title}',
        );
        if (showSuccessToast && toastContext.mounted) {
          LifeOsTopToast.show(
            toastContext,
            'Đã thêm "${draft.title}" vào giỏ đi chợ.',
          );
        }
        return true;

      case OmniActionKind.waterLog:
        if (dailyBloc == null) return false;
        final ml = draft.waterMl > 0 ? draft.waterMl : 250;
        dailyBloc.add(WaterIntakeLogged(userId: user.id, deltaMl: ml));
        await UserBehaviorPrefs.recordHabitExecution(
          label: 'Uống ${ml}ml nước',
          commandText: 'Uống ${ml}ml nước',
        );
        if (showSuccessToast && toastContext.mounted) {
          LifeOsTopToast.show(
            toastContext,
            'Đã ghi nhận +$ml ml nước uống hôm nay.',
          );
        }
        return true;

      case OmniActionKind.medication:
        if (dailyBloc == null) return false;
        final sched = draft.scheduledAt;
        dailyBloc.add(
          MedicationCabinetAdded(
            userId: user.id,
            name: draft.title,
            dosage: draft.dosage,
            slot: draft.medicationSlot,
            remainingPills: 30,
            expiryDate: DateTime.now().add(const Duration(days: 270)),
            reminderEnabled: true,
            reminderHour: sched?.hour ?? draft.medicationSlot.defaultHour,
            reminderMinute: sched?.minute ?? draft.medicationSlot.defaultMinute,
          ),
        );
        await UserBehaviorPrefs.recordHabitExecution(
          label: 'Thuốc ${draft.title}',
          commandText: 'Nhắc uống thuốc ${draft.title}',
        );
        if (showSuccessToast && toastContext.mounted) {
          LifeOsTopToast.show(
            toastContext,
            'Đã đặt chuông nhắc uống thuốc: "${draft.title}".',
          );
        }
        return true;
    }
  }
}
