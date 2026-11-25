import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/error/failure.dart';
import 'package:life_os/core/security/bank_notification_parser.dart';
import 'package:life_os/features/family/data/repositories/family_repository_impl.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/family/domain/usecases/family_usecases.dart';
import 'package:life_os/features/family/presentation/bloc/family_bloc.dart';

void main() {
  group('FIX-002 & FIX-003: Atomic Join, 3 Invite Modes & PII Zeroing', () {
    test(
      'One-time invite works atomically without reading families before join and rejects 2nd user replay',
      () async {
        final fs = FakeFirebaseFirestore();
        final ownerDs = FamilyRemoteDataSource(fs);
        final ownerRepo = FamilyRepositoryImpl(ownerDs);

        final fam =
            (await ownerRepo.createFamily(
                      userId: 'u_owner',
                      userName: 'Minh',
                      familyName: 'Gia đình Minh',
                    )
                    as Success<FamilyEntity>)
                .value;

        final code =
            (await ownerRepo.createInviteCode(
                      userId: 'u_owner',
                      familyId: fam.id,
                      familyName: fam.name,
                      invitedByName: 'Minh',
                      inviteKind: InviteKind.oneTime,
                    )
                    as Success<String>)
                .value;

        final invSnap = await fs.collection('family_invites').doc(code).get();
        expect(invSnap.exists, isTrue);
        expect(invSnap.data()?['inviteKind'], 'oneTime');
        expect(invSnap.data()?['maxUses'], 1);
        expect(invSnap.data()?['usedCount'], 0);
        expect(invSnap.data()?['status'], 'active');
        expect(invSnap.data()?.containsKey('inviteeContact'), isFalse);

        final preview =
            (await ownerRepo.previewInviteCode(inviteCode: code)
                    as Success<FamilyPendingInviteEntity>)
                .value;
        expect(preview.inviteKind, InviteKind.oneTime);
        expect(preview.maxUses, 1);
        expect(preview.usedCount, 0);
        expect(preview.status, InviteStatus.active);
        expect(preview.inviteeContact, isNull);

        final joinerAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'u_joiner_1', email: 'joiner1@lifeos.vn'),
        );
        final joinerRepo = FamilyRepositoryImpl(
          FamilyRemoteDataSource(fs, firebaseAuth: joinerAuth),
        );

        final joined =
            (await joinerRepo.joinFamilyByInvite(
                      userId: 'u_joiner_1',
                      userName: 'Lan',
                      inviteCode: code,
                    )
                    as Success<FamilyEntity>)
                .value;

        expect(joined.memberIds, containsAll(['u_owner', 'u_joiner_1']));
        expect(joined.roleOf('u_joiner_1'), HouseholdRole.member);
        expect(joined.pendingInvites, isEmpty);

        final afterInv = await fs.collection('family_invites').doc(code).get();
        expect(afterInv.data()?['usedCount'], 1);
        expect(afterInv.data()?['consumedBy'], 'u_joiner_1');
        expect(afterInv.data()?['consumedAt'], isNotNull);
        expect(afterInv.data()?['status'], 'consumed');

        final userDoc = await fs.collection('users').doc('u_joiner_1').get();
        expect(userDoc.data()?['activeFamilyId'], fam.id);
        expect(userDoc.data()?['familyIds'], contains(fam.id));

        // 2nd user replaying consumed oneTime invite MUST be rejected!
        final replayAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'u_replay', email: 'replay@lifeos.vn'),
        );
        final replayRepo = FamilyRepositoryImpl(
          FamilyRemoteDataSource(fs, firebaseAuth: replayAuth),
        );
        final replayRes = await replayRepo.joinFamilyByInvite(
          userId: 'u_replay',
          userName: 'Kẻ lạ',
          inviteCode: code,
        );
        expect(replayRes, isA<Err<FamilyEntity>>());
      },
    );

    test(
      'Targeted invite strips raw PII from public doc, validates normalized email/VN-phone SHA-256, and rejects intruders',
      () async {
        final fs = FakeFirebaseFirestore();
        final ownerRepo = FamilyRepositoryImpl(FamilyRemoteDataSource(fs));

        final fam =
            (await ownerRepo.createFamily(
                      userId: 'u_owner',
                      userName: 'Hòa',
                      familyName: 'Nhà Trọ Xanh',
                      spaceType: CollaborationSpaceType.roommates,
                    )
                    as Success<FamilyEntity>)
                .value;

        // Even if someone passes an email/phone inside inviteeName, public doc strips it!
        final code =
            (await ownerRepo.createInviteCode(
                      userId: 'u_owner',
                      familyId: fam.id,
                      familyName: fam.name,
                      inviteKind: InviteKind.targeted,
                      inviteeName: '0909123456',
                      inviteeContact: '+84 909-123-456',
                    )
                    as Success<String>)
                .value;

        final publicInv = await fs.collection('family_invites').doc(code).get();
        expect(publicInv.data()?.containsKey('inviteeContact'), isFalse);
        expect(publicInv.data()?.containsKey('inviteeName'), isFalse);
        expect(
          publicInv.data()?['intendedRecipientHash'],
          FamilyInviteCodeExtractor.hashRecipientContact('0909 123 456'),
        );

        // Internal family doc keeps inviteeContact for group managers only
        final famDoc = await fs.collection('families').doc(fam.id).get();
        final internalPending =
            (famDoc.data()?['pendingInvites'] as Map)[code] as Map;
        expect(internalPending['inviteeContact'], '+84 909-123-456');

        // Attacker with different email/phone who even tries to spoof their users/{uid} profile is rejected!
        await fs.collection('users').doc('u_attacker').set({
          'id': 'u_attacker',
          'email': '0909123456', // spoofed profile field
        });
        final attackerAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: 'u_attacker',
            email: 'attacker@evil.vn',
            phoneNumber: '+84911111111',
          ),
        );
        final attackerRepo = FamilyRepositoryImpl(
          FamilyRemoteDataSource(fs, firebaseAuth: attackerAuth),
        );
        final rejected = await attackerRepo.joinFamilyByInvite(
          userId: 'u_attacker',
          userName: 'Attacker',
          inviteCode: code,
        );
        expect(rejected, isA<Err<FamilyEntity>>());
        expect(
          (rejected as Err<FamilyEntity>).failure,
          isA<PermissionDeniedFailure>(),
        );

        // Legitimate recipient with local 0909123456 phone number matches +84 hash and joins!
        final targetAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: 'u_target',
            email: 'lan@lifeos.vn',
            phoneNumber: '0909123456',
          ),
        );
        final targetRepo = FamilyRepositoryImpl(
          FamilyRemoteDataSource(fs, firebaseAuth: targetAuth),
        );
        final joined = await targetRepo.joinFamilyByInvite(
          userId: 'u_target',
          userName: 'Lan',
          inviteCode: code,
        );
        expect(joined, isA<Success<FamilyEntity>>());
        expect(
          (joined as Success<FamilyEntity>).value.roleOf('u_target'),
          HouseholdRole.member,
        );
      },
    );

    test(
      'ReusableGroup invite supports N=3 members, idempotent re-join, revoke & CloudFunctionsInvoker bridge',
      () async {
        final fs = FakeFirebaseFirestore();
        final ownerRepo = FamilyRepositoryImpl(FamilyRemoteDataSource(fs));

        final fam =
            (await ownerRepo.createFamily(
                      userId: 'u_owner',
                      userName: 'Minh',
                      familyName: 'Nhóm Du Lịch Đà Lạt',
                      spaceType: CollaborationSpaceType.group,
                    )
                    as Success<FamilyEntity>)
                .value;

        // Invalid maxUses for oneTime or reusableGroup rejected
        final badOneTime = await ownerRepo.createInviteCode(
          userId: 'u_owner',
          familyId: fam.id,
          familyName: fam.name,
          inviteKind: InviteKind.oneTime,
          maxUses: 3,
        );
        expect(badOneTime, isA<Err<String>>());

        final badTargeted = await ownerRepo.createInviteCode(
          userId: 'u_owner',
          familyId: fam.id,
          familyName: fam.name,
          inviteKind: InviteKind.targeted,
        );
        expect(badTargeted, isA<Err<String>>());

        final groupCode =
            (await ownerRepo.createInviteCode(
                      userId: 'u_owner',
                      familyId: fam.id,
                      familyName: fam.name,
                      inviteKind: InviteKind.reusableGroup,
                      maxUses: 3,
                    )
                    as Success<String>)
                .value;

        for (final uid in ['u_1', 'u_2', 'u_3']) {
          final repo = FamilyRepositoryImpl(
            FamilyRemoteDataSource(
              fs,
              firebaseAuth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: uid, email: '$uid@lifeos.vn'),
              ),
            ),
          );
          final res = await repo.joinFamilyByInvite(
            userId: uid,
            userName: 'Thành viên $uid',
            inviteCode: groupCode,
          );
          expect(res, isA<Success<FamilyEntity>>());
        }

        // 4th user rejected after maxUses=3 exhausted
        final fourthRes = await ownerRepo.joinFamilyByInvite(
          userId: 'u_4',
          userName: 'Thành viên 4',
          inviteCode: groupCode,
        );
        expect(fourthRes, isA<Err<FamilyEntity>>());

        // Revocation atomically updates both family_invites and families.pendingInvites
        final revCode =
            (await ownerRepo.createInviteCode(
                      userId: 'u_owner',
                      familyId: fam.id,
                      familyName: fam.name,
                      inviteKind: InviteKind.reusableGroup,
                      maxUses: 5,
                    )
                    as Success<String>)
                .value;
        final revokeRes = await ownerRepo.revokeInviteCode(
          actorUserId: 'u_owner',
          familyId: fam.id,
          inviteCode: revCode,
        );
        expect(revokeRes, isA<Success<void>>());
        final revDoc = await fs.collection('family_invites').doc(revCode).get();
        expect(revDoc.data()?['revoked'], isTrue);
        expect(revDoc.data()?['status'], 'revoked');
        expect(revDoc.data()?['revokedAt'], isNotNull);

        // Injectable CloudFunctionsInvoker path verification
        final invokedCalls = <String>[];
        final cfDs = FamilyRemoteDataSource(
          fs,
          functionsInvoker: (fn, payload) async {
            invokedCalls.add(fn);
            return switch (fn) {
              'createFamilyInvite' => {'ok': true, 'inviteCode': 'FAM-CF9999'},
              'previewFamilyInvite' => {
                'ok': true,
                'inviteCode': 'FAM-CF9999',
                'familyId': fam.id,
                'familyName': fam.name,
                'spaceType': 'group',
                'inviteKind': 'reusableGroup',
                'invitedByName': 'Minh',
                'maxUses': 5,
                'usedCount': 1,
                'status': 'active',
                'expiresAtMs': DateTime.now()
                    .add(const Duration(days: 7))
                    .millisecondsSinceEpoch,
              },
              'joinFamilyByInvite' => {
                'ok': true,
                'familyId': fam.id,
                'familyName': fam.name,
                'spaceType': 'group',
              },
              _ => {'ok': true},
            };
          },
        );
        final cfCode = await cfDs.createInviteCode(
          userId: 'u_owner',
          familyId: fam.id,
          familyName: fam.name,
          inviteKind: InviteKind.reusableGroup,
          maxUses: 5,
        );
        expect(cfCode, 'FAM-CF9999');
        final cfPrev = await cfDs.previewInviteCode(inviteCode: cfCode);
        expect(cfPrev.maxUses, 5);
        expect(cfPrev.usedCount, 1);
        final cfJoined = await cfDs.joinFamilyByInvite(
          userId: 'u_1',
          userName: 'Bạn 1',
          inviteCode: cfCode,
        );
        expect(cfJoined.id, fam.id);
        await cfDs.revokeInviteCode(
          actorUserId: 'u_owner',
          familyId: fam.id,
          inviteCode: cfCode,
        );
        expect(invokedCalls, [
          'createFamilyInvite',
          'previewFamilyInvite',
          'joinFamilyByInvite',
          'revokeFamilyInvite',
        ]);
      },
    );
  });

  group('FIX-006: Hybrid DebtSimplifier, 2-Step Settlements & Reversals', () {
    test(
      'Eliminates ghost bank_transfer member and resolves deterministic SPLIT code settlements cleanly',
      () {
        final now = DateTime.utc(2026, 11, 25);
        const members = [
          FamilyMemberInfo(
            userId: 'u_an',
            fullName: 'An',
            role: HouseholdRole.owner,
          ),
          FamilyMemberInfo(
            userId: 'u_binh',
            fullName: 'Bình',
            role: HouseholdRole.member,
          ),
        ];
        final bills = [
          SharedBillSplitEntity(
            id: 'b1',
            familyId: 'fam_1',
            title: 'Ăn lẩu',
            topic: SharedExpenseTopic.dining,
            paidByUserId: 'u_an',
            paidByName: 'An',
            totalAmountMinor: 200000,
            splitMethod: SplitMethod.equal,
            sharesByUserId: const {'u_an': 100000, 'u_binh': 100000},
            participantNames: const {'u_an': 'An', 'u_binh': 'Bình'},
            createdAt: now,
          ),
        ];

        // Case 1: Unmatched `'bank_transfer'` record must NEVER create ghost member or corrupt net-zero!
        final unresolvedSummary = DebtSimplifier.summarize(
          familyId: 'fam_1',
          members: members,
          bills: bills,
          settlements: [
            DebtSettlementEntity(
              id: 'auto_unknown',
              familyId: 'fam_1',
              fromUserId: 'bank_transfer',
              fromUserName: 'NGUYEN VAN X',
              toUserId: 'u_an',
              toUserName: 'An',
              amountMinor: 100000,
              paymentCode: 'LIFEOS SPLIT UNKNOWN',
              createdAt: now,
            ),
          ],
        );
        expect(
          unresolvedSummary.memberBalances.any(
            (b) => b.userId == 'bank_transfer',
          ),
          isFalse,
        );
        expect(
          unresolvedSummary.memberBalances.fold<int>(
            0,
            (s, b) => s + b.netBalanceMinor,
          ),
          0,
        );
        expect(
          unresolvedSummary.suggestedTransfers.single.fromUserId,
          'u_binh',
        );
        expect(unresolvedSummary.suggestedTransfers.single.toUserId, 'u_an');
        expect(unresolvedSummary.suggestedTransfers.single.amountMinor, 100000);

        // Case 2: `'bank_transfer'` carrying Bình's deterministic SPLIT code settles Bình -> An cleanly!
        final binhCode = BankNotificationParser.buildSePayTransferCode(
          scopePrefix: 'SPLIT',
          seed: 'fam_1:u_binh:u_an:100000',
        );
        final resolvedSummary = DebtSimplifier.summarize(
          familyId: 'fam_1',
          members: members,
          bills: bills,
          settlements: [
            DebtSettlementEntity(
              id: 'auto_matched',
              familyId: 'fam_1',
              fromUserId: 'bank_transfer',
              fromUserName: 'TRAN BINH',
              toUserId: 'u_an',
              toUserName: 'An',
              amountMinor: 100000,
              paymentCode: binhCode,
              createdAt: now,
            ),
          ],
        );
        expect(
          resolvedSummary.memberBalances.any(
            (b) => b.userId == 'bank_transfer',
          ),
          isFalse,
        );
        expect(resolvedSummary.suggestedTransfers, isEmpty);
        expect(
          resolvedSummary.memberBalances.every((b) => b.netBalanceMinor == 0),
          isTrue,
        );
      },
    );

    test(
      'Exact Subset-Sum DP beats Greedy on decomposable subgroups (M<=12) and bounded Greedy scales for M>12',
      () {
        final now = DateTime.utc(2026, 11, 25);

        // Classic counterexample where Greedy needs 4 transfers, Exact DP finds 3:
        // Net balances: A:+100k, B:+50k, C:-70k, D:-50k, E:-30k
        // Constructed cleanly via 2 zero-sum bills paid by A(100k) and B(50k)?? Wait:
        // Total spend = 150k: A pays 120k (shares: A=20k, C=70k, E=30k -> A:+100k, C:-70k, E:-30k),
        // B pays 50k (shares: D=50k -> B:+50k, D:-50k).
        final members5 = const [
          FamilyMemberInfo(
            userId: 'u_a',
            fullName: 'A',
            role: HouseholdRole.owner,
          ),
          FamilyMemberInfo(
            userId: 'u_b',
            fullName: 'B',
            role: HouseholdRole.member,
          ),
          FamilyMemberInfo(
            userId: 'u_c',
            fullName: 'C',
            role: HouseholdRole.member,
          ),
          FamilyMemberInfo(
            userId: 'u_d',
            fullName: 'D',
            role: HouseholdRole.member,
          ),
          FamilyMemberInfo(
            userId: 'u_e',
            fullName: 'E',
            role: HouseholdRole.member,
          ),
        ];
        final bills5 = [
          SharedBillSplitEntity(
            id: 'b_a',
            familyId: 'fam_dp',
            title: 'Bill A',
            topic: SharedExpenseTopic.dining,
            paidByUserId: 'u_a',
            paidByName: 'A',
            totalAmountMinor: 120000,
            splitMethod: SplitMethod.exact,
            sharesByUserId: const {'u_a': 20000, 'u_c': 70000, 'u_e': 30000},
            participantNames: const {'u_a': 'A', 'u_c': 'C', 'u_e': 'E'},
            createdAt: now,
          ),
          SharedBillSplitEntity(
            id: 'b_b',
            familyId: 'fam_dp',
            title: 'Bill B',
            topic: SharedExpenseTopic.utilities,
            paidByUserId: 'u_b',
            paidByName: 'B',
            totalAmountMinor: 50000,
            splitMethod: SplitMethod.exact,
            sharesByUserId: const {'u_d': 50000},
            participantNames: const {'u_d': 'D'},
            createdAt: now,
          ),
        ];

        final dpSummary = DebtSimplifier.summarize(
          familyId: 'fam_dp',
          members: members5,
          bills: bills5,
          settlements: const [],
        );
        expect(dpSummary.isExactOptimal, isTrue);
        expect(dpSummary.suggestedTransfers.length, 3);
        expect(
          dpSummary.suggestedTransfers.any(
            (t) =>
                t.fromUserId == 'u_d' &&
                t.toUserId == 'u_b' &&
                t.amountMinor == 50000,
          ),
          isTrue,
        );

        // Large group M=15 (> 12) switches to bounded Greedy (isExactOptimal == false) and preserves conservation
        final members15 = List.generate(
          15,
          (i) => FamilyMemberInfo(
            userId: 'u_${i.toString().padLeft(2, '0')}',
            fullName: 'Member $i',
            role: i == 0 ? HouseholdRole.owner : HouseholdRole.member,
          ),
        );
        final shares15 = <String, int>{
          for (var i = 0; i < 15; i++)
            'u_${i.toString().padLeft(2, '0')}': 100000 + i * 1000,
        };
        final total15 = shares15.values.fold<int>(0, (s, v) => s + v);
        final summary15 = DebtSimplifier.summarize(
          familyId: 'fam_15',
          members: members15,
          bills: [
            SharedBillSplitEntity(
              id: 'b_15',
              familyId: 'fam_15',
              title: 'Year-end party',
              topic: SharedExpenseTopic.travel,
              paidByUserId: 'u_00',
              paidByName: 'Member 0',
              totalAmountMinor: total15,
              splitMethod: SplitMethod.exact,
              sharesByUserId: shares15,
              participantNames: {
                for (final m in members15) m.userId: m.fullName,
              },
              createdAt: now,
            ),
          ],
          settlements: const [],
        );
        expect(summary15.isExactOptimal, isFalse);
        expect(summary15.suggestedTransfers.length, 14);
        expect(
          summary15.memberBalances.fold<int>(
            0,
            (s, b) => s + b.netBalanceMinor,
          ),
          0,
        );
      },
    );

    test(
      'Property test (200 randomized scenarios): zero-sum invariant, positive transfers, exact conservation & deterministic output',
      () {
        final rng = Random(20261125);
        final now = DateTime.utc(2026, 11, 25);

        for (var trial = 0; trial < 200; trial++) {
          final n =
              2 +
              rng.nextInt(13); // 2..14 members (covers both Exact DP & Greedy)
          final members = List.generate(
            n,
            (i) => FamilyMemberInfo(
              userId: 'm_${i.toString().padLeft(2, '0')}',
              fullName: 'User $i',
              role: i == 0 ? HouseholdRole.owner : HouseholdRole.member,
            ),
          );
          final bills = <SharedBillSplitEntity>[];
          final billCount = 1 + rng.nextInt(6);
          for (var b = 0; b < billCount; b++) {
            final payer = members[rng.nextInt(n)];
            final total = 10000 + rng.nextInt(990000);
            final partIds = <String>[
              for (final m in members)
                if (rng.nextBool()) m.userId,
            ];
            if (partIds.isEmpty) partIds.add(members[rng.nextInt(n)].userId);
            final shares = SplitBillCalculator.computeEqualSplit(
              totalAmountMinor: total,
              participantIds: partIds,
              payerUserId: payer.userId,
            );
            bills.add(
              SharedBillSplitEntity(
                id: 'b_${trial}_$b',
                familyId: 'fam_prop',
                title: 'Bill $b',
                topic: SharedExpenseTopic
                    .values[b % SharedExpenseTopic.values.length],
                paidByUserId: payer.userId,
                paidByName: payer.fullName,
                totalAmountMinor: total,
                splitMethod: SplitMethod.equal,
                sharesByUserId: shares,
                participantNames: {
                  for (final m in members) m.userId: m.fullName,
                },
                createdAt: now,
              ),
            );
          }

          final s1 = DebtSimplifier.summarize(
            familyId: 'fam_prop',
            members: members,
            bills: bills,
            settlements: const [],
          );
          final s2 = DebtSimplifier.summarize(
            familyId: 'fam_prop',
            members: members.reversed.toList(),
            bills: bills.reversed.toList(),
            settlements: const [],
          );

          // Determinism
          expect(s1.suggestedTransfers, equals(s2.suggestedTransfers));

          // Zero-sum invariant
          final netMap = <String, int>{
            for (final mb in s1.memberBalances) mb.userId: mb.netBalanceMinor,
          };
          expect(netMap.values.fold<int>(0, (s, v) => s + v), 0);

          // Conservation after applying all transfers
          for (final tr in s1.suggestedTransfers) {
            expect(tr.amountMinor, greaterThan(0));
            expect(tr.fromUserId, isNot(equals(tr.toUserId)));
            netMap[tr.fromUserId] =
                (netMap[tr.fromUserId] ?? 0) + tr.amountMinor;
            netMap[tr.toUserId] = (netMap[tr.toUserId] ?? 0) - tr.amountMinor;
          }
          expect(netMap.values.every((v) => v == 0), isTrue);
        }
      },
    );

    test(
      'Partial settlements, 2-step settlement_requests (pending->confirm/reject), and append-only contra reversals work in Repository & FamilyBloc',
      () async {
        final fs = FakeFirebaseFirestore();
        final repo = FamilyRepositoryImpl(FamilyRemoteDataSource(fs));
        final bloc = FamilyBloc(
          repository: repo,
          createFamily: CreateFamilyUseCase(repo),
          joinFamily: JoinFamilyByCodeUseCase(repo),
        );

        final fam =
            (await repo.createFamily(
                      userId: 'u_creditor',
                      userName: 'An',
                      familyName: 'Nhóm Cân Đối',
                    )
                    as Success<FamilyEntity>)
                .value;
        final code =
            (await repo.createInviteCode(
                      userId: 'u_creditor',
                      familyId: fam.id,
                      familyName: fam.name,
                    )
                    as Success<String>)
                .value;
        await repo.joinFamilyByInvite(
          userId: 'u_debtor',
          userName: 'Bình',
          inviteCode: code,
        );

        bloc.add(const FamilySubscriptionRequested(userId: 'u_creditor'));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // An pays 300,000 split equally -> Bình owes An 150,000
        bloc.add(
          SharedBillSplitCreated(
            CreateSharedBillSplitParams(
              familyId: fam.id,
              title: 'Mua đồ dùng chung',
              topic: SharedExpenseTopic.housework,
              paidByUserId: 'u_creditor',
              paidByName: 'An',
              totalAmountMinor: 300000,
              splitMethod: SplitMethod.equal,
              participantIds: const ['u_creditor', 'u_debtor'],
              participantNames: const {'u_creditor': 'An', 'u_debtor': 'Bình'},
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(
          bloc.state.sharedLedger.suggestedTransfers.single.amountMinor,
          150000,
        );

        // Step 1: Debtor requests a PARTIAL settlement of 50,000 VND
        bloc.add(
          DebtSettlementRequested(
            RequestDebtSettlementParams(
              familyId: fam.id,
              fromUserId: 'u_debtor',
              fromUserName: 'Bình',
              toUserId: 'u_creditor',
              toUserName: 'An',
              amountMinor: 50000,
              isPartial: true,
              note: 'Trả trước 50k',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(bloc.state.pendingSettlementRequests.length, 1);
        final req = bloc.state.pendingSettlementRequests.single;
        expect(req.isPartial, isTrue);
        // Before creditor confirms, debt remains 150,000!
        expect(
          bloc.state.sharedLedger.suggestedTransfers.single.amountMinor,
          150000,
        );

        // Non-creditor (debtor) trying to self-confirm MUST be denied!
        final selfConfirm = await repo.confirmSettlementRequest(
          familyId: fam.id,
          requestId: req.id,
          actorUserId: 'u_debtor',
          approve: true,
        );
        expect(selfConfirm, isA<Err<DebtSettlementEntity?>>());
        expect(
          (selfConfirm as Err<DebtSettlementEntity?>).failure,
          isA<PermissionDeniedFailure>(),
        );

        // Step 2: Creditor confirms -> reduces remaining debt from 150,000 -> 100,000!
        bloc.add(
          SettlementRequestDecided(
            ConfirmSettlementRequestParams(
              familyId: fam.id,
              requestId: req.id,
              actorUserId: 'u_creditor',
              approve: true,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(bloc.state.pendingSettlementRequests, isEmpty);
        expect(bloc.state.settlements.length, 1);
        expect(
          bloc.state.sharedLedger.suggestedTransfers.single.amountMinor,
          100000,
        );

        // Second partial direct settlement (40,000) -> remaining debt 60,000
        bloc.add(
          DebtSettlementRecorded(
            RecordDebtSettlementParams(
              familyId: fam.id,
              fromUserId: 'u_debtor',
              fromUserName: 'Bình',
              toUserId: 'u_creditor',
              toUserName: 'An',
              amountMinor: 40000,
              paymentCode: 'LIFEOS SPLIT PART2',
              isPartial: true,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(
          bloc.state.sharedLedger.suggestedTransfers.single.amountMinor,
          60000,
        );

        // Reverse the 40,000 settlement via append-only contra entry -> remaining debt restores to 100,000!
        final part2 = bloc.state.settlements.firstWhere(
          (s) => s.amountMinor == 40000,
        );
        bloc.add(
          DebtSettlementReversed(
            ReverseDebtSettlementParams(
              familyId: fam.id,
              settlementId: part2.id,
              actorUserId: 'u_creditor',
              reason: 'Nhập nhầm số tiền',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(bloc.state.settlements.any((s) => s.isReversal), isTrue);
        expect(
          bloc.state.sharedLedger.suggestedTransfers.single.amountMinor,
          100000,
        );

        // Double-reversal is idempotently blocked with ConflictFailure!
        final doubleRev = await repo.reverseDebtSettlement(
          familyId: fam.id,
          settlementId: part2.id,
          actorUserId: 'u_creditor',
        );
        expect(doubleRev, isA<Err<DebtSettlementEntity>>());
        expect(
          (doubleRev as Err<DebtSettlementEntity>).failure,
          isA<ConflictFailure>(),
        );

        // Rejected settlement request leaves balances untouched
        final rejectReq =
            (await repo.requestDebtSettlement(
                      familyId: fam.id,
                      fromUserId: 'u_debtor',
                      fromUserName: 'Bình',
                      toUserId: 'u_creditor',
                      toUserName: 'An',
                      amountMinor: 100000,
                      paymentCode: 'LIFEOS SPLIT DISPUTED',
                    )
                    as Success<SettlementRequestEntity>)
                .value;
        bloc.add(
          SettlementRequestDecided(
            ConfirmSettlementRequestParams(
              familyId: fam.id,
              requestId: rejectReq.id,
              actorUserId: 'u_creditor',
              approve: false,
              disputeReason: 'Chưa thấy biến động số dư',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(
          bloc.state.settlementRequests
              .firstWhere((r) => r.id == rejectReq.id)
              .status,
          SettlementRequestStatus.rejected,
        );
        expect(
          bloc.state.sharedLedger.suggestedTransfers.single.amountMinor,
          100000,
        );

        await bloc.close();
      },
    );
  });
}
