import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../app/config/firebase_config.dart';
import '../../../../core/error/app_exception.dart';
import '../models/user_model.dart';

typedef GoogleAuthHandler = Future<UserCredential> Function(FirebaseAuth auth);

class FirebaseAuthRemoteDataSource {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final GoogleAuthHandler? _googleAuthOverride;

  FirebaseAuthRemoteDataSource({
    required FirebaseAuth firebaseAuth,
    required FirebaseFirestore firestore,
    GoogleAuthHandler? googleAuthOverride,
  })  : _firebaseAuth = firebaseAuth,
        _firestore = firestore,
        _googleAuthOverride = googleAuthOverride;

  static const List<({String id, String name, String direction, String iconKey})>
      _defaultCategories = [
    (id: 'cat_food', name: 'Ăn uống', direction: 'debit', iconKey: 'restaurant'),
    (
      id: 'cat_housework',
      name: 'Việc nhà & Gia dụng',
      direction: 'debit',
      iconKey: 'cleaning_services'
    ),
    (id: 'cat_housing', name: 'Nhà cửa & Thuê nhà', direction: 'debit', iconKey: 'home'),
    (id: 'cat_utilities', name: 'Điện/Nước/Internet', direction: 'debit', iconKey: 'bolt'),
    (id: 'cat_shopping', name: 'Chợ & Mua sắm', direction: 'debit', iconKey: 'shopping_bag'),
    (id: 'cat_vehicle', name: 'Xe cộ & Di chuyển', direction: 'debit', iconKey: 'two_wheeler'),
    (id: 'cat_vehicle_maint', name: 'Bảo dưỡng & Sửa xe', direction: 'debit', iconKey: 'build'),
    (id: 'cat_health', name: 'Sức khỏe & Giáo dục', direction: 'debit', iconKey: 'favorite'),
    (
      id: 'cat_entertainment',
      name: 'Giải trí & Đăng ký',
      direction: 'debit',
      iconKey: 'subscriptions'
    ),
    (id: 'cat_family_social', name: 'Hiếu hỉ & Đối ngoại', direction: 'debit', iconKey: 'redeem'),
    (id: 'cat_debt', name: 'Trả nợ & Cho vay', direction: 'debit', iconKey: 'RequestQuote'),
    (id: 'cat_bank_fee', name: 'Phí ngân hàng', direction: 'debit', iconKey: 'account_balance'),
    (id: 'cat_other_exp', name: 'Chi tiêu khác', direction: 'debit', iconKey: 'category'),
    (id: 'cat_salary', name: 'Lương & Thu nhập', direction: 'credit', iconKey: 'payments'),
    (id: 'cat_other_inc', name: 'Thu nhập khác', direction: 'credit', iconKey: 'savings'),
  ];

  static List<String> _extractProviders(User fbUser, {String? ensureIncluded}) {
    final set = <String>{
      for (final info in fbUser.providerData)
        if (info.providerId.isNotEmpty) info.providerId,
    };
    if (ensureIncluded != null && ensureIncluded.isNotEmpty) {
      set.add(ensureIncluded);
    }
    if (set.isEmpty) {
      set.add('password');
    }
    return set.toList();
  }

  static String _deriveDisplayName({String? displayName, String? email}) {
    final trimmed = displayName?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    final cleanEmail = email?.trim() ?? '';
    if (cleanEmail.contains('@')) {
      final prefix = cleanEmail.split('@').first.trim();
      if (prefix.isNotEmpty) return prefix;
    }
    return 'Người dùng Life OS';
  }

  Stream<UserModel?> watchUser() {
    final initialAndChanges = Stream<User?>.multi((controller) {
      controller.addSync(_firebaseAuth.currentUser);
      final sub = _firebaseAuth.authStateChanges().listen(
            controller.addSync,
            onError: controller.addErrorSync,
            onDone: controller.closeSync,
          );
      controller.onCancel = sub.cancel;
    });

    return initialAndChanges.asyncExpand((firebaseUser) {
      if (firebaseUser == null) {
        return Stream<UserModel?>.value(null);
      }
      final userRef = _firestore.collection('users').doc(firebaseUser.uid);
      return userRef.snapshots().asyncMap((snap) async {
        if (!snap.exists) {
          return _ensurePersonalSpaceInitialized(
            uid: firebaseUser.uid,
            email: firebaseUser.email ?? '',
            fullName: _deriveDisplayName(
              displayName: firebaseUser.displayName,
              email: firebaseUser.email,
            ),
            photoUrl: firebaseUser.photoURL,
            phoneNumber: firebaseUser.phoneNumber,
            emailVerified: firebaseUser.emailVerified,
            authProviders: _extractProviders(firebaseUser),
          );
        }
        return UserModel.fromFirestore(snap);
      });
    });
  }

  Future<UserModel> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
  }) async {
    final cred = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final fbUser = cred.user;
    if (fbUser == null) {
      throw const AppException(
        code: 'AUTH_FAILURE',
        message: 'Không thể khởi tạo tài khoản.',
      );
    }
    await fbUser.updateDisplayName(fullName);
    try {
      await fbUser.sendEmailVerification();
    } catch (_) {
      // Safe no-op in offline/mock environments where SMTP dispatch is unavailable.
    }
    return _ensurePersonalSpaceInitialized(
      uid: fbUser.uid,
      email: email,
      fullName: fullName,
      phoneNumber: phoneNumber?.trim().isNotEmpty == true ? phoneNumber!.trim() : null,
      photoUrl: fbUser.photoURL,
      emailVerified: fbUser.emailVerified,
      authProviders: _extractProviders(fbUser, ensureIncluded: 'password'),
    );
  }

  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final cred = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final fbUser = cred.user;
    if (fbUser == null) {
      throw const AppException(
        code: 'AUTH_FAILURE',
        message: 'Đăng nhập không thành công.',
      );
    }
    final userRef = _firestore.collection('users').doc(fbUser.uid);
    final snap = await userRef.get();
    if (!snap.exists) {
      return _ensurePersonalSpaceInitialized(
        uid: fbUser.uid,
        email: fbUser.email ?? email,
        fullName: _deriveDisplayName(displayName: fbUser.displayName, email: email),
        photoUrl: fbUser.photoURL,
        phoneNumber: fbUser.phoneNumber,
        emailVerified: fbUser.emailVerified,
        authProviders: _extractProviders(fbUser, ensureIncluded: 'password'),
      );
    }
    final existing = UserModel.fromFirestore(snap);
    final mergedProviders = <String>{
      ...existing.authProviders,
      ..._extractProviders(fbUser, ensureIncluded: 'password'),
    }.toList();
    if (fbUser.emailVerified != existing.emailVerified ||
        mergedProviders.length != existing.authProviders.length) {
      await userRef.update({
        'emailVerified': fbUser.emailVerified || existing.emailVerified,
        'authProviders': mergedProviders,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      final refreshed = await userRef.get();
      return UserModel.fromFirestore(refreshed);
    }
    return existing;
  }

  GoogleAuthProvider _buildGoogleProvider() {
    return GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile')
      ..setCustomParameters(const <String, String>{'prompt': 'select_account'});
  }

  Future<void> _ensureGoogleInitialized() {
    return FirebaseConfig.ensureGoogleSignInInitialized();
  }

  Future<UserCredential> _obtainGoogleUserCredential() async {
    final override = _googleAuthOverride;
    if (override != null) {
      return override(_firebaseAuth);
    }

    final provider = _buildGoogleProvider();
    if (kIsWeb) {
      return _firebaseAuth.signInWithPopup(provider);
    }

    // Against local Firebase Auth Emulator, Federated Provider flow opens the official
    // Emulator Google Sign-In picker directly without Play Services SHA-1 mismatch.
    if (FirebaseConfig.shouldUseEmulator) {
      return _firebaseAuth.signInWithProvider(provider);
    }

    try {
      await _ensureGoogleInitialized();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        return await _firebaseAuth.signInWithProvider(provider);
      }
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const <String>['email', 'profile'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        return await _firebaseAuth.signInWithProvider(provider);
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      return await _firebaseAuth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AppException(
          code: 'AUTH_CANCELED',
          message: 'Bạn đã hủy đăng nhập bằng Google.',
        );
      }
      // Seamless fallback to Firebase Federated OAuth Custom Tab if Play Services One-Tap
      // lacks Web Client ID or is temporarily unavailable on custom Android OEM ROMs.
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError ||
          e.code == GoogleSignInExceptionCode.providerConfigurationError ||
          e.code == GoogleSignInExceptionCode.uiUnavailable ||
          e.code == GoogleSignInExceptionCode.unknownError) {
        return _firebaseAuth.signInWithProvider(provider);
      }
      rethrow;
    } on UnsupportedError {
      return _firebaseAuth.signInWithProvider(provider);
    }
  }

  Future<UserModel> signInWithGoogle() async {
    final cred = await _obtainGoogleUserCredential();
    final fbUser = cred.user;
    if (fbUser == null) {
      throw const AppException(
        code: 'AUTH_FAILURE',
        message: 'Không nhận được thông tin tài khoản từ Google.',
      );
    }

    final userRef = _firestore.collection('users').doc(fbUser.uid);
    final snap = await userRef.get();
    final providers = _extractProviders(fbUser, ensureIncluded: 'google.com');

    if (!snap.exists) {
      return _ensurePersonalSpaceInitialized(
        uid: fbUser.uid,
        email: fbUser.email ?? '',
        fullName: _deriveDisplayName(
          displayName: fbUser.displayName,
          email: fbUser.email,
        ),
        photoUrl: fbUser.photoURL,
        phoneNumber: fbUser.phoneNumber,
        emailVerified: true,
        authProviders: providers,
      );
    }

    final existing = UserModel.fromFirestore(snap);
    final mergedProviders = <String>{
      ...existing.authProviders,
      ...providers,
    }.toList();
    final resolvedName =
        existing.fullName.trim().isEmpty || existing.fullName == 'Người dùng Life OS'
            ? _deriveDisplayName(displayName: fbUser.displayName, email: fbUser.email)
            : existing.fullName;

    await userRef.update({
      'fullName': resolvedName,
      if (fbUser.email != null && fbUser.email!.isNotEmpty) 'email': fbUser.email,
      if (fbUser.photoURL != null && fbUser.photoURL!.isNotEmpty) 'photoUrl': fbUser.photoURL,
      'emailVerified': true,
      'authProviders': mergedProviders,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
    final updatedSnap = await userRef.get();
    return UserModel.fromFirestore(updatedSnap);
  }

  Future<UserModel> linkGoogleAccount() async {
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser == null) {
      throw const AppException(
        code: 'PERMISSION_DENIED',
        message: 'Vui lòng đăng nhập trước khi liên kết tài khoản Google.',
      );
    }

    UserCredential linkedCred;
    final provider = _buildGoogleProvider();
    if (kIsWeb) {
      linkedCred = await currentUser.linkWithPopup(provider);
    } else if (FirebaseConfig.shouldUseEmulator) {
      linkedCred = await currentUser.linkWithProvider(provider);
    } else {
      try {
        await _ensureGoogleInitialized();
        final account = await GoogleSignIn.instance.authenticate(
          scopeHint: const <String>['email', 'profile'],
        );
        final idToken = account.authentication.idToken;
        if (idToken != null && idToken.isNotEmpty) {
          linkedCred = await currentUser.linkWithCredential(
            GoogleAuthProvider.credential(idToken: idToken),
          );
        } else {
          linkedCred = await currentUser.linkWithProvider(provider);
        }
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) {
          throw const AppException(
            code: 'AUTH_CANCELED',
            message: 'Bạn đã hủy liên kết tài khoản Google.',
          );
        }
        linkedCred = await currentUser.linkWithProvider(provider);
      }
    }

    final updatedFbUser = linkedCred.user ?? currentUser;
    final userRef = _firestore.collection('users').doc(updatedFbUser.uid);
    final snap = await userRef.get();
    final existingProviders =
        snap.exists ? UserModel.fromFirestore(snap).authProviders : const <String>[];
    final mergedProviders = <String>{
      ...existingProviders,
      ..._extractProviders(updatedFbUser, ensureIncluded: 'google.com'),
    }.toList();

    await userRef.set(
      {
        'photoUrl': updatedFbUser.photoURL,
        'emailVerified': true,
        'authProviders': mergedProviders,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      },
      SetOptions(merge: true),
    );
    final refreshed = await userRef.get();
    return UserModel.fromFirestore(refreshed);
  }

  Future<UserModel> _ensurePersonalSpaceInitialized({
    required String uid,
    required String email,
    required String fullName,
    String? photoUrl,
    String? phoneNumber,
    bool emailVerified = false,
    List<String> authProviders = const <String>['password'],
  }) async {
    final now = DateTime.now();
    final userModel = UserModel(
      id: uid,
      email: email,
      fullName: fullName,
      photoUrl: photoUrl,
      phoneNumber: phoneNumber,
      emailVerified: emailVerified,
      authProviders: authProviders,
      timezone: 'Asia/Ho_Chi_Minh',
      onboardingCompleted: false,
      availabilityOptIn: false,
      createdAt: now,
      updatedAt: now,
    );

    final batch = _firestore.batch();
    final userDoc = _firestore.collection('users').doc(uid);
    batch.set(userDoc, userModel.toFirestore(), SetOptions(merge: true));

    final cashWalletDoc = userDoc.collection('wallets').doc('wallet_cash_default');
    batch.set(
      cashWalletDoc,
      {
        'id': 'wallet_cash_default',
        'ownerId': uid,
        'name': 'Ví tiền mặt',
        'type': 'cash',
        'balanceMinor': 0,
        'isEstimatedBalance': true,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      },
      SetOptions(merge: true),
    );

    final bankWalletDoc = userDoc.collection('wallets').doc('wallet_bank_default');
    batch.set(
      bankWalletDoc,
      {
        'id': 'wallet_bank_default',
        'ownerId': uid,
        'name': 'Ngân hàng Thanh toán',
        'type': 'bank',
        'bankCode': 'NAPAS247',
        'maskedAccount': 'SePay · Auto-Sync',
        'balanceMinor': 0,
        'isEstimatedBalance': false,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      },
      SetOptions(merge: true),
    );

    final savingsWalletDoc = userDoc.collection('wallets').doc('wallet_savings_default');
    batch.set(
      savingsWalletDoc,
      {
        'id': 'wallet_savings_default',
        'ownerId': uid,
        'name': 'Sổ Tiết kiệm Tích lũy',
        'type': 'savings',
        'maskedAccount': 'Lãi kép mục tiêu',
        'balanceMinor': 0,
        'isEstimatedBalance': false,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      },
      SetOptions(merge: true),
    );

    final emergencyFundDoc = userDoc.collection('personal_funds').doc('fund_emergency_default');
    batch.set(
      emergencyFundDoc,
      {
        'id': 'fund_emergency_default',
        'ownerId': uid,
        'name': 'Quỹ Dự phòng Khẩn cấp (6 Tháng)',
        'targetAmountMinor': 60000000,
        'balanceMinor': 0,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      },
      SetOptions(merge: true),
    );

    for (final cat in _defaultCategories) {
      batch.set(
        userDoc.collection('categories').doc(cat.id),
        {
          'id': cat.id,
          'ownerId': uid,
          'name': cat.name,
          'direction': cat.direction,
          'iconKey': cat.iconKey,
          'isSystem': true,
        },
        SetOptions(merge: true),
      );
    }

    batch.set(
      userDoc.collection('consents').doc('android_notification'),
      {
        'sourceId': 'android_notification',
        'ownerId': uid,
        'enabled': false,
        'allowedPackages': <String>[],
        'updatedAt': Timestamp.fromDate(now),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
    return userModel;
  }

  Future<void> sendPasswordReset({required String email}) {
    return _firebaseAuth.sendPasswordResetEmail(email: email);
  }

  Future<void> sendEmailVerification() async {
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser == null) {
      throw const AppException(
        code: 'PERMISSION_DENIED',
        message: 'Không tìm thấy phiên đăng nhập hiện tại.',
      );
    }
    await currentUser.sendEmailVerification();
  }

  Future<UserModel> reloadCurrentUser() async {
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser == null) {
      throw const AppException(
        code: 'PERMISSION_DENIED',
        message: 'Không tìm thấy phiên đăng nhập hiện tại.',
      );
    }
    try {
      await currentUser.reload();
    } catch (_) {
      // Safe fallback for mock auth instances that do not implement network reload.
    }
    final refreshedUser = _firebaseAuth.currentUser ?? currentUser;
    final userRef = _firestore.collection('users').doc(refreshedUser.uid);
    final snap = await userRef.get();
    if (!snap.exists) {
      return _ensurePersonalSpaceInitialized(
        uid: refreshedUser.uid,
        email: refreshedUser.email ?? '',
        fullName: _deriveDisplayName(
          displayName: refreshedUser.displayName,
          email: refreshedUser.email,
        ),
        photoUrl: refreshedUser.photoURL,
        phoneNumber: refreshedUser.phoneNumber,
        emailVerified: refreshedUser.emailVerified,
        authProviders: _extractProviders(refreshedUser),
      );
    }
    final existing = UserModel.fromFirestore(snap);
    final mergedProviders = <String>{
      ...existing.authProviders,
      ..._extractProviders(refreshedUser),
    }.toList();
    await userRef.update({
      'emailVerified': refreshedUser.emailVerified || existing.emailVerified,
      if (refreshedUser.photoURL != null && refreshedUser.photoURL!.isNotEmpty)
        'photoUrl': refreshedUser.photoURL,
      'authProviders': mergedProviders,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
    final updatedSnap = await userRef.get();
    return UserModel.fromFirestore(updatedSnap);
  }

  Future<UserModel> updateUserProfile({
    required String userId,
    required String fullName,
    String? phoneNumber,
    String? timezone,
  }) async {
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser != null && currentUser.uid == userId) {
      await currentUser.updateDisplayName(fullName);
    }
    final ref = _firestore.collection('users').doc(userId);
    final updates = <String, dynamic>{
      'fullName': fullName,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
    if (phoneNumber != null) {
      updates['phoneNumber'] = phoneNumber.trim().isEmpty ? null : phoneNumber.trim();
    }
    if (timezone != null && timezone.trim().isNotEmpty) {
      updates['timezone'] = timezone.trim();
    }
    await ref.update(updates);
    final snap = await ref.get();
    return UserModel.fromFirestore(snap);
  }

  Future<UserModel> changePassword({
    required String userId,
    String? currentPassword,
    required String newPassword,
  }) async {
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser == null || currentUser.uid != userId) {
      throw const AppException(
        code: 'PERMISSION_DENIED',
        message: 'Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại.',
      );
    }
    final email = currentUser.email ?? '';
    final ref = _firestore.collection('users').doc(userId);
    final snap = await ref.get();
    final existing = snap.exists ? UserModel.fromFirestore(snap) : null;
    final hasPassword = existing?.authProviders.contains('password') ??
        currentUser.providerData.any((p) => p.providerId == 'password');

    if (hasPassword) {
      if (email.isNotEmpty && currentPassword != null && currentPassword.isNotEmpty) {
        final cred = EmailAuthProvider.credential(
          email: email,
          password: currentPassword,
        );
        await currentUser.reauthenticateWithCredential(cred);
      }
      await currentUser.updatePassword(newPassword);
    } else {
      if (email.isEmpty) {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message: 'Tài khoản chưa có email để thiết lập mật khẩu.',
        );
      }
      final cred = EmailAuthProvider.credential(email: email, password: newPassword);
      await currentUser.linkWithCredential(cred);
    }

    final mergedProviders = <String>{
      ...(existing?.authProviders ?? const <String>[]),
      'password',
    }.toList();
    await ref.update({
      'authProviders': mergedProviders,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
    final updatedSnap = await ref.get();
    return UserModel.fromFirestore(updatedSnap);
  }

  Future<UserModel> completeOnboarding({required String userId}) async {
    final ref = _firestore.collection('users').doc(userId);
    await ref.update({
      'onboardingCompleted': true,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
    final snap = await ref.get();
    return UserModel.fromFirestore(snap);
  }

  Future<UserModel> updatePrivacySettings({
    required String userId,
    bool? availabilityOptIn,
    String? activeFamilyId,
  }) async {
    final ref = _firestore.collection('users').doc(userId);
    final updates = <String, dynamic>{
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
    if (availabilityOptIn != null) {
      updates['availabilityOptIn'] = availabilityOptIn;
    }
    if (activeFamilyId != null) {
      updates['activeFamilyId'] = activeFamilyId.isEmpty ? null : activeFamilyId;
    }
    await ref.update(updates);
    final snap = await ref.get();
    return UserModel.fromFirestore(snap);
  }

  Future<void> signOut() async {
    if (!kIsWeb && FirebaseConfig.isGoogleSignInInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Ignore platform signOut failure when not signed in via Google Play Services.
      }
    }
    await _firebaseAuth.signOut();
  }
}
