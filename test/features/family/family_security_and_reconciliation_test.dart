import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/error/failure.dart';
import 'package:life_os/features/authentication/domain/entities/user_entity.dart';
import 'package:life_os/features/authentication/domain/repositories/auth_repository.dart';
import 'package:life_os/features/authentication/domain/usecases/auth_usecases.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_bloc.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_event.dart';
import 'package:life_os/features/family/data/repositories/family_repository_impl.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/family/domain/usecases/family_usecases.dart';
import 'package:life_os/features/family/presentation/bloc/family_bloc.dart';
import 'package:life_os/features/family/presentation/pages/family_page.dart';

class _StubAuthRepository extends Fake implements AuthRepository {
  final UserEntity _user;
  _StubAuthRepository(this._user);

  @override
  Stream<UserEntity?> watchCurrentUser() => Stream.value(_user);
}

class _PermissionDeniedWriteBatch extends Fake implements WriteBatch {
  @override
  void update<T>(DocumentReference<T> document, T data) {}

  @override
  void set<T>(
    DocumentReference<T> document,
    T data, [
    SetOptions? options,
  ]) {}

  @override
  Future<void> commit() async {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Missing or insufficient permissions.',
    );
  }
}

class _PermissionDeniedBatchFirestore extends FakeFirebaseFirestore {
  @override
  WriteBatch batch() => _PermissionDeniedWriteBatch();
}

void main() {
  group('Finding 2 — Targeted Invite Verified Email & Rules Denial Mapping', () {
    test(
      'Targeted invite requires verified email, binds inviteeUid/email/hash, preserves open invites & maps permission-denied',
      () async {
        final fs = FakeFirebaseFirestore();
        final ownerRepo = FamilyRepositoryImpl(FamilyRemoteDataSource(fs));

        final fam =
            (await ownerRepo.createFamily(
                      userId: 'u_owner',
                      userName: 'Minh',
                      familyName: 'Tổ ấm Gia đình',
                    )
                    as Success<FamilyEntity>)
                .value;

        // 1. Targeted invite via email (stored as intendedRecipientHash on public doc)
        final targetedCode =
            (await ownerRepo.createInviteCode(
                      userId: 'u_owner',
                      familyId: fam.id,
                      familyName: fam.name,
                      inviteKind: InviteKind.targeted,
                      inviteeName: 'Lan',
                      inviteeContact: 'Lan@LifeOS.vn',
                    )
                    as Success<String>)
                .value;

        // 1a. Unverified matching email MUST fail with clear Vietnamese message
        final unverifiedRepo = FamilyRepositoryImpl(
          FamilyRemoteDataSource(
            fs,
            firebaseAuth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(
                uid: 'u_lan',
                email: 'lan@lifeos.vn',
                isEmailVerified: false,
              ),
            ),
          ),
        );
        final unverifiedRes = await unverifiedRepo.joinFamilyByInvite(
          userId: 'u_lan',
          userName: 'Lan',
          inviteCode: targetedCode,
        );
        expect(unverifiedRes, isA<Err<FamilyEntity>>());
        final unverifiedFailure = (unverifiedRes as Err<FamilyEntity>).failure;
        expect(unverifiedFailure, isA<PermissionDeniedFailure>());
        expect(
          unverifiedFailure.message,
          contains('Cần xác minh email trước khi tham gia nhóm'),
        );

        // 1b. Different verified user with the same valid code MUST be rejected
        final intruderRepo = FamilyRepositoryImpl(
          FamilyRemoteDataSource(
            fs,
            firebaseAuth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(
                uid: 'u_intruder',
                email: 'intruder@lifeos.vn',
                isEmailVerified: true,
              ),
            ),
          ),
        );
        final intruderRes = await intruderRepo.joinFamilyByInvite(
          userId: 'u_intruder',
          userName: 'Kẻ lạ',
          inviteCode: targetedCode,
        );
        expect(intruderRes, isA<Err<FamilyEntity>>());
        expect(
          (intruderRes as Err<FamilyEntity>).failure,
          isA<PermissionDeniedFailure>(),
        );

        // 1c. Verified matching email (case-insensitive) joins cleanly
        final verifiedRepo = FamilyRepositoryImpl(
          FamilyRemoteDataSource(
            fs,
            firebaseAuth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(
                uid: 'u_lan',
                email: 'lan@lifeos.vn',
                isEmailVerified: true,
              ),
            ),
          ),
        );
        final joinedLan = await verifiedRepo.joinFamilyByInvite(
          userId: 'u_lan',
          userName: 'Lan',
          inviteCode: targetedCode,
        );
        expect(joinedLan, isA<Success<FamilyEntity>>());
        expect(
          (joinedLan as Success<FamilyEntity>).value.memberIds,
          contains('u_lan'),
        );

        // 2. Targeted invite with inviteeEmail (legacy / direct field) enforces verified email
        const emailCode = 'FAM-EMAIL88';
        await fs.collection('family_invites').doc(emailCode).set({
          'inviteId': emailCode,
          'inviteCode': emailCode,
          'familyId': fam.id,
          'familyName': fam.name,
          'spaceType': 'family',
          'inviteKind': 'targeted',
          'isTargeted': true,
          'inviteeEmail': 'Mai@LifeOS.vn',
          'createdBy': 'u_owner',
          'invitedByUserId': 'u_owner',
          'invitedByName': 'Minh',
          'maxUses': 1,
          'usedCount': 0,
          'revoked': false,
          'status': 'active',
          'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 3)),
          ),
          'createdAt': Timestamp.fromDate(DateTime.now()),
        });
        final maiUnverified = await FamilyRepositoryImpl(
          FamilyRemoteDataSource(
            fs,
            firebaseAuth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(
                uid: 'u_mai',
                email: 'mai@lifeos.vn',
                isEmailVerified: false,
              ),
            ),
          ),
        ).joinFamilyByInvite(
          userId: 'u_mai',
          userName: 'Mai',
          inviteCode: emailCode,
        );
        expect(maiUnverified, isA<Err<FamilyEntity>>());
        expect(
          (maiUnverified as Err<FamilyEntity>).failure.message,
          contains('Cần xác minh email trước khi tham gia nhóm'),
        );
        final maiVerified = await FamilyRepositoryImpl(
          FamilyRemoteDataSource(
            fs,
            firebaseAuth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(
                uid: 'u_mai',
                email: 'mai@lifeos.vn',
                isEmailVerified: true,
              ),
            ),
          ),
        ).joinFamilyByInvite(
          userId: 'u_mai',
          userName: 'Mai',
          inviteCode: emailCode,
        );
        expect(maiVerified, isA<Success<FamilyEntity>>());

        // 3. Targeted invite with inviteeUid: only matching UID joins
        const uidCode = 'FAM-UID999';
        await fs.collection('family_invites').doc(uidCode).set({
          'inviteId': uidCode,
          'inviteCode': uidCode,
          'familyId': fam.id,
          'familyName': fam.name,
          'spaceType': 'family',
          'inviteKind': 'targeted',
          'isTargeted': true,
          'inviteeUid': 'u_bob_exact',
          'createdBy': 'u_owner',
          'invitedByUserId': 'u_owner',
          'invitedByName': 'Minh',
          'maxUses': 1,
          'usedCount': 0,
          'revoked': false,
          'status': 'active',
          'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 3)),
          ),
          'createdAt': Timestamp.fromDate(DateTime.now()),
        });
        final wrongUidRes = await FamilyRepositoryImpl(
          FamilyRemoteDataSource(
            fs,
            firebaseAuth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'u_not_bob', isEmailVerified: true),
            ),
          ),
        ).joinFamilyByInvite(
          userId: 'u_not_bob',
          userName: 'Fake Bob',
          inviteCode: uidCode,
        );
        expect(wrongUidRes, isA<Err<FamilyEntity>>());
        final rightUidRes = await FamilyRepositoryImpl(
          FamilyRemoteDataSource(
            fs,
            firebaseAuth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'u_bob_exact'),
            ),
          ),
        ).joinFamilyByInvite(
          userId: 'u_bob_exact',
          userName: 'Bob',
          inviteCode: uidCode,
        );
        expect(rightUidRes, isA<Success<FamilyEntity>>());

        // 4. Open invite still works without verified email
        final openCode =
            (await ownerRepo.createInviteCode(
                      userId: 'u_owner',
                      familyId: fam.id,
                      familyName: fam.name,
                      inviteKind: InviteKind.oneTime,
                    )
                    as Success<String>)
                .value;
        final openJoiner = FamilyRepositoryImpl(
          FamilyRemoteDataSource(
            fs,
            firebaseAuth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(
                uid: 'u_open_guest',
                email: 'guest@lifeos.vn',
                isEmailVerified: false,
              ),
            ),
          ),
        );
        final openJoined = await openJoiner.joinFamilyByInvite(
          userId: 'u_open_guest',
          userName: 'Khách',
          inviteCode: openCode,
        );
        expect(openJoined, isA<Success<FamilyEntity>>());

        // 5. Rules permission-denied on batch commit maps to clear Vietnamese prompt
        final deniedFs = _PermissionDeniedBatchFirestore();
        final seedOwner = FamilyRepositoryImpl(FamilyRemoteDataSource(deniedFs));
        final deniedFam =
            (await seedOwner.createFamily(
                      userId: 'u_owner',
                      userName: 'Minh',
                      familyName: 'Nhóm Kiểm Thử',
                    )
                    as Success<FamilyEntity>)
                .value;
        const blockedCode = 'FAM-RULES1';
        await deniedFs.collection('family_invites').doc(blockedCode).set({
          'inviteId': blockedCode,
          'inviteCode': blockedCode,
          'familyId': deniedFam.id,
          'familyName': deniedFam.name,
          'spaceType': 'family',
          'inviteKind': 'oneTime',
          'isTargeted': false,
          'createdBy': 'u_owner',
          'invitedByUserId': 'u_owner',
          'invitedByName': 'Minh',
          'maxUses': 1,
          'usedCount': 0,
          'revoked': false,
          'status': 'active',
          'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 3)),
          ),
          'createdAt': Timestamp.fromDate(DateTime.now()),
        });
        final deniedDs = FamilyRemoteDataSource(
          deniedFs,
          firebaseAuth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'u_new_joiner'),
          ),
        );
        await expectLater(
          () => deniedDs.joinFamilyByInvite(
            userId: 'u_new_joiner',
            userName: 'An',
            inviteCode: blockedCode,
          ),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', 'PERMISSION_DENIED')
                .having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains('cập nhật ứng dụng'),
                    contains('gửi lại lời mời'),
                  ),
                ),
          ),
        );
      },
    );
  });

  group('Finding 7 — Split Bill Share Invariant & Legacy Reconciliation UI', () {
    test(
      'Splits 100.000đ among 3 cleanly, rejects mismatched sums & >20 members, and isolates legacy mismatched bills',
      () async {
        final fs = FakeFirebaseFirestore();
        final ds = FamilyRemoteDataSource(fs);
        final repo = FamilyRepositoryImpl(ds);
        final useCase = CreateSharedBillSplitUseCase(repo);

        final fam =
            (await repo.createFamily(
                      userId: 'u_1',
                      userName: 'An',
                      familyName: 'Nhà Chung',
                    )
                    as Success<FamilyEntity>)
                .value;

        // 1. Split 100.000đ among 3 to the last đồng (33.334 / 33.333 / 33.333)
        final exact3Res = await useCase(
          CreateSharedBillSplitParams(
            familyId: fam.id,
            title: 'Cà phê sáng 3 người',
            topic: SharedExpenseTopic.dining,
            paidByUserId: 'u_1',
            paidByName: 'An',
            totalAmountMinor: 100000,
            splitMethod: SplitMethod.equal,
            participantIds: const ['u_1', 'u_2', 'u_3'],
            participantNames: const {
              'u_1': 'An',
              'u_2': 'Bình',
              'u_3': 'Chi',
            },
          ),
        );
        expect(exact3Res, isA<Success<SharedBillSplitEntity>>());
        final bill3 = (exact3Res as Success<SharedBillSplitEntity>).value;
        expect(bill3.sharesByUserId, {'u_1': 33334, 'u_2': 33333, 'u_3': 33333});
        expect(bill3.sharesSumMinor, 100000);
        expect(bill3.isSharesBalanced, isTrue);
        expect(bill3.needsReconciliation, isFalse);
        expect(
          bill3.reconciliationStatus,
          SharedBillReconciliationStatus.reconciled,
        );

        // 2. Mismatched sum rejected in both UseCase and DataSource
        final mismatchedUseCase = await useCase(
          CreateSharedBillSplitParams(
            familyId: fam.id,
            title: 'Hóa đơn lệch tổng',
            topic: SharedExpenseTopic.dining,
            paidByUserId: 'u_1',
            paidByName: 'An',
            totalAmountMinor: 100000,
            splitMethod: SplitMethod.exact,
            participantIds: const ['u_1', 'u_2'],
            participantNames: const {'u_1': 'An', 'u_2': 'Bình'},
            rawInputValuesByUserId: const {'u_1': 40000, 'u_2': 40000},
          ),
        );
        expect(mismatchedUseCase, isA<Err<SharedBillSplitEntity>>());

        await expectLater(
          () => ds.createSharedBillSplit(
            familyId: fam.id,
            title: 'Ghi trực tiếp lệch tổng',
            topic: SharedExpenseTopic.dining,
            paidByUserId: 'u_1',
            paidByName: 'An',
            totalAmountMinor: 100000,
            splitMethod: SplitMethod.exact,
            sharesByUserId: const {'u_1': 40000, 'u_2': 40000},
            participantNames: const {'u_1': 'An', 'u_2': 'Bình'},
          ),
          throwsA(isA<AppException>()),
        );

        // 3. Exceeding 20 participants rejected in both UseCase and DataSource
        final tooManyIds = List.generate(21, (i) => 'u_${i + 1}');
        final tooManyNames = {for (final id in tooManyIds) id: 'Thành viên $id'};
        final tooManyUseCase = await useCase(
          CreateSharedBillSplitParams(
            familyId: fam.id,
            title: 'Quá 20 người',
            topic: SharedExpenseTopic.other,
            paidByUserId: 'u_1',
            paidByName: 'An',
            totalAmountMinor: 210000,
            splitMethod: SplitMethod.equal,
            participantIds: tooManyIds,
            participantNames: tooManyNames,
          ),
        );
        expect(tooManyUseCase, isA<Err<SharedBillSplitEntity>>());

        await expectLater(
          () => ds.createSharedBillSplit(
            familyId: fam.id,
            title: 'Quá 20 người direct',
            topic: SharedExpenseTopic.other,
            paidByUserId: 'u_1',
            paidByName: 'An',
            totalAmountMinor: 210000,
            splitMethod: SplitMethod.equal,
            sharesByUserId: {for (final id in tooManyIds) id: 10000},
            participantNames: tooManyNames,
          ),
          throwsA(isA<AppException>()),
        );

        // 4. Legacy mismatched bill detection + clean isolation in DebtSimplifier
        final legacyBroken = SharedBillSplitEntity(
          id: 'bill_legacy_skew',
          familyId: fam.id,
          title: 'Hóa đơn cũ lệch tổng',
          topic: SharedExpenseTopic.utilities,
          paidByUserId: 'u_1',
          paidByName: 'An',
          totalAmountMinor: 150000,
          splitMethod: SplitMethod.exact,
          sharesByUserId: const {'u_1': 50000, 'u_2': 50000},
          participantNames: const {'u_1': 'An', 'u_2': 'Bình'},
          createdAt: DateTime(2026, 11, 1),
        );
        expect(legacyBroken.needsReconciliation, isTrue);
        expect(
          legacyBroken.reconciliationStatus.displayLabel,
          'Cần đối soát',
        );
        expect(legacyBroken.discrepancyMinor, 50000);

        final summary = DebtSimplifier.summarize(
          familyId: fam.id,
          members: const [
            FamilyMemberInfo(
              userId: 'u_1',
              fullName: 'An',
              role: HouseholdRole.owner,
            ),
            FamilyMemberInfo(
              userId: 'u_2',
              fullName: 'Bình',
              role: HouseholdRole.member,
            ),
            FamilyMemberInfo(
              userId: 'u_3',
              fullName: 'Chi',
              role: HouseholdRole.member,
            ),
          ],
          bills: [bill3, legacyBroken],
          settlements: const [],
        );
        expect(summary.totalSharedSpendMinor, 100000);
        expect(summary.inconsistentBillCount, 1);
        expect(summary.inconsistentBillIds, const ['bill_legacy_skew']);
        expect(summary.unverifiedSharedSpendMinor, 150000);
        expect(summary.needsReconciliation, isTrue);
        final anBal = summary.memberBalances.firstWhere(
          (b) => b.userId == 'u_1',
        );
        expect(anBal.netBalanceMinor, 66666);
      },
    );

    testWidgets(
      'Bill UI and debt UI both show "Cần đối soát" and consistent reconciled amounts at 360x800 @ 1.2x',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFirestore = FakeFirebaseFirestore();
        const ownerUid = 'u_owner_f7';
        const memberUid = 'u_member_f7';

        final authRepo = _StubAuthRepository(
          UserEntity(
            id: ownerUid,
            email: 'owner@lifeos.vn',
            fullName: 'Nguyễn Minh',
            emailVerified: true,
            timezone: 'Asia/Ho_Chi_Minh',
            onboardingCompleted: true,
            availabilityOptIn: false,
            activeFamilyId: 'fam_f7_ui',
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        final familyRepo = FamilyRepositoryImpl(
          FamilyRemoteDataSource(fakeFirestore),
        );

        final famRef = fakeFirestore.collection('families').doc('fam_f7_ui');
        await famRef.set({
          'id': 'fam_f7_ui',
          'name': 'Tổ ấm Đối Soát',
          'spaceType': 'family',
          'createdBy': ownerUid,
          'memberIds': [ownerUid, memberUid],
          'memberRoles': {ownerUid: 'owner', memberUid: 'member'},
          'memberNames': {ownerUid: 'Nguyễn Minh', memberUid: 'Trần Lan'},
          'createdAt': Timestamp.now(),
        });

        await fakeFirestore.collection('users').doc(ownerUid).set({
          'id': ownerUid,
          'name': 'Nguyễn Minh',
          'email': 'owner@lifeos.vn',
          'familyId': 'fam_f7_ui',
          'activeFamilyId': 'fam_f7_ui',
          'familyIds': ['fam_f7_ui'],
        });

        // 1 valid reconciled bill (90.000đ -> Minh 30k, Lan 60k)
        await famRef.collection('split_bills').doc('bill_ok').set({
          'id': 'bill_ok',
          'familyId': 'fam_f7_ui',
          'title': 'Bữa tối hợp lệ',
          'topic': 'dining',
          'paidByUserId': ownerUid,
          'paidByName': 'Nguyễn Minh',
          'totalAmountMinor': 90000,
          'splitMethod': 'exact',
          'sharesByUserId': {ownerUid: 30000, memberUid: 60000},
          'participantNames': {ownerUid: 'Nguyễn Minh', memberUid: 'Trần Lan'},
          'status': 'open',
          'createdAt': Timestamp.now(),
        });

        // 1 legacy inconsistent bill (100.000đ vs shares sum 70.000đ)
        await famRef.collection('split_bills').doc('bill_bad_legacy').set({
          'id': 'bill_bad_legacy',
          'familyId': 'fam_f7_ui',
          'title': 'Hóa đơn cũ lệch tổng',
          'topic': 'utilities',
          'paidByUserId': ownerUid,
          'paidByName': 'Nguyễn Minh',
          'totalAmountMinor': 100000,
          'splitMethod': 'exact',
          'sharesByUserId': {ownerUid: 35000, memberUid: 35000},
          'participantNames': {ownerUid: 'Nguyễn Minh', memberUid: 'Trần Lan'},
          'status': 'open',
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(hours: 1)),
          ),
        });

        final authBloc = AuthBloc(
          watchCurrentUser: WatchCurrentUserUseCase(authRepo),
          signIn: SignInUseCase(authRepo),
          signUp: SignUpUseCase(authRepo),
          signInWithGoogle: SignInWithGoogleUseCase(authRepo),
          linkGoogleAccount: LinkGoogleAccountUseCase(authRepo),
          sendPasswordReset: SendPasswordResetUseCase(authRepo),
          sendEmailVerification: SendEmailVerificationUseCase(authRepo),
          reloadCurrentUser: ReloadCurrentUserUseCase(authRepo),
          updateUserProfile: UpdateUserProfileUseCase(authRepo),
          changePassword: ChangePasswordUseCase(authRepo),
          completeOnboarding: CompleteOnboardingUseCase(authRepo),
          updatePrivacySettings: UpdatePrivacySettingsUseCase(authRepo),
          signOut: SignOutUseCase(authRepo),
        )..add(const AuthSubscriptionRequested());
        final familyBloc = FamilyBloc(
          repository: familyRepo,
          createFamily: CreateFamilyUseCase(familyRepo),
          joinFamily: JoinFamilyByCodeUseCase(familyRepo),
          createSharedBillSplit: CreateSharedBillSplitUseCase(familyRepo),
          recordDebtSettlement: RecordDebtSettlementUseCase(familyRepo),
        )..add(const FamilySubscriptionRequested(userId: ownerUid));
        addTearDown(() async {
          await tester.runAsync(() async {
            await authBloc.close().timeout(
              const Duration(seconds: 1),
              onTimeout: () {},
            );
            await familyBloc.close().timeout(
              const Duration(seconds: 1),
              onTimeout: () {},
            );
          });
        });

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider<FamilyBloc>.value(value: familyBloc),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const MediaQuery(
                data: MediaQueryData(
                  size: Size(360, 800),
                  textScaler: TextScaler.linear(1.2),
                ),
                child: FamilyPage(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        final verticalScrollable = find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first;

        // Hero summary discloses reconciled figure inside "Chi tiết sổ chung"
        await tester.tap(find.text('Chi tiết sổ chung'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('Tổng chi đã đối soát: 90.000'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Cân đối chi tiêu thành viên'),
          250,
          scrollable: verticalScrollable,
        );
        await tester.pump();
        expect(find.text('Cân đối chi tiêu thành viên'), findsOneWidget);
        expect(find.text('Cần đối soát'), findsWidgets);
        expect(find.textContaining('Nhận lại 60.000'), findsOneWidget);

        // Scroll to bill UI ("Sổ Khoản chi Chung (2)") and verify both bills render accurately
        await tester.scrollUntilVisible(
          find.text('Sổ Khoản chi Chung (2)'),
          250,
          scrollable: verticalScrollable,
        );
        await tester.pump();
        expect(find.text('Sổ Khoản chi Chung (2)'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Bữa tối hợp lệ'),
          250,
          scrollable: verticalScrollable,
        );
        await tester.pump();
        expect(find.text('Đã ghi sổ chung'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('Hóa đơn cũ lệch tổng'),
          250,
          scrollable: verticalScrollable,
        );
        await tester.pump();
        expect(find.text('Cần đối soát'), findsWidgets);
        expect(
          find.textContaining('Tổng hóa đơn 100.000'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Tổng phần chia 70.000'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
