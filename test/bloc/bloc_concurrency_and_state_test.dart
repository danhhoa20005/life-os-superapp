import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:life_os/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_bloc.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_event.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockTransactionRepository extends Mock
    implements TransactionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(WalletType.cash);
    registerFallbackValue(TransactionKind.expense);
  });

  group('BLoC Event → State & bloc_concurrency Verification', () {
    blocTest<ThemeBloc, ThemeState>(
      'ThemeBloc processes ThemeModeChanged and HighContrastToggled sequentially without Cubit',
      build: ThemeBloc.new,
      act: (bloc) {
        bloc
          ..add(const ThemeModeChanged(ThemeMode.dark))
          ..add(const HighContrastToggled(true));
      },
      expect: () => const [
        ThemeState(themeMode: ThemeMode.dark, highContrast: false),
        ThemeState(themeMode: ThemeMode.dark, highContrast: true),
      ],
    );

    test(
      'TransactionActionBloc processes sequential writes in strict order and guards validation',
      () async {
        final mockRepo = _MockTransactionRepository();
        var callCount = 0;

        when(
          () => mockRepo.createTransaction(
            operationId: any(named: 'operationId'),
            userId: any(named: 'userId'),
            walletId: any(named: 'walletId'),
            targetWalletId: any(named: 'targetWalletId'),
            categoryId: any(named: 'categoryId'),
            categoryName: any(named: 'categoryName'),
            kind: any(named: 'kind'),
            amountMinor: any(named: 'amountMinor'),
            merchant: any(named: 'merchant'),
            note: any(named: 'note'),
            occurredAt: any(named: 'occurredAt'),
            splitLines: any(named: 'splitLines'),
          ),
        ).thenAnswer((inv) async {
          callCount += 1;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          final opId = inv.namedArguments[#operationId] as String;
          final amt = inv.namedArguments[#amountMinor] as int;
          return Success(
            TransactionEntity(
              id: opId,
              ownerId: 'u1',
              walletId: 'w1',
              categoryName: 'Ăn uống',
              kind: TransactionKind.expense,
              direction: 'debit',
              amountMinor: amt,
              merchant: 'Quán cơm',
              occurredAt: DateTime.utc(2026, 11, 22),
              monthKey: '2026-11',
              sourceKind: TransactionSourceKind.manual,
              verification: TransactionVerification.userConfirmed,
              crossSourceFingerprint: 'fp_$opId',
            ),
          );
        });

        final bloc = TransactionActionBloc(
          createWallet: CreateWalletUseCase(mockRepo),
          createTransaction: CreateTransactionUseCase(mockRepo),
          reverseTransaction: ReverseTransactionUseCase(mockRepo),
          decideProvisional: DecideProvisionalTransactionUseCase(mockRepo),
        );

        final states = <TransactionActionState>[];
        final sub = bloc.stream.listen(states.add);

        final now = DateTime.utc(2026, 11, 22);
        bloc
          ..add(
            TransactionCreateSubmitted(
              operationId: 'op_1',
              userId: 'u1',
              walletId: 'w1',
              categoryName: 'Ăn uống',
              kind: TransactionKind.expense,
              amountMinor: 85000,
              merchant: 'Phở sáng',
              occurredAt: now,
            ),
          )
          ..add(
            TransactionCreateSubmitted(
              operationId: 'op_2',
              userId: 'u1',
              walletId: 'w1',
              categoryName: 'Ăn uống',
              kind: TransactionKind.expense,
              amountMinor: 45000,
              merchant: 'Cà phê',
              occurredAt: now,
            ),
          );

        await Future<void>.delayed(const Duration(milliseconds: 140));
        expect(callCount, 2);
        final createdAmounts = states
            .where(
              (s) =>
                  s.status == ActionStatus.success &&
                  s.lastCreatedTransaction != null,
            )
            .map((s) => s.lastCreatedTransaction!.amountMinor)
            .toList();
        expect(createdAmounts, [85000, 45000]);

        await sub.cancel();
        await bloc.close();
      },
    );

    test(
      'CreateTransactionUseCase enforces exact VND sum invariant on multi-category Split Transactions',
      () async {
        final mockRepo = _MockTransactionRepository();
        final useCase = CreateTransactionUseCase(mockRepo);
        final now = DateTime.utc(2026, 11, 22);

        final mismatchRes = await useCase(
          CreateTransactionParams(
            operationId: 'op_split_bad',
            userId: 'u1',
            walletId: 'w1',
            categoryName: 'Ăn uống',
            kind: TransactionKind.expense,
            amountMinor: 500000,
            merchant: 'Siêu thị',
            occurredAt: now,
            splitLines: const [
              TransactionSplitLine(
                categoryName: 'Ăn uống',
                amountMinor: 300000,
              ),
              TransactionSplitLine(
                categoryName: 'Việc nhà & Gia dụng',
                amountMinor: 150000,
              ),
            ],
          ),
        );
        expect(mismatchRes, isA<Err<TransactionEntity>>());
      },
    );
  });
}
