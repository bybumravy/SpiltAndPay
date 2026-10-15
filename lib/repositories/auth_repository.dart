import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/firebase_providers.dart';
import '../models/app_user.dart';
import 'user_repository.dart';

/// Xử lý đăng nhập, đăng ký, và đăng xuất.
class AuthRepository {
  final FirebaseAuth _auth;
  final UserRepository _userRepo;

  AuthRepository(this._auth, this._userRepo);

  /// Đăng nhập bằng Google.
  /// Nếu user mới → tạo document profile trong Firestore.
  Future<User> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) throw Exception('Đăng nhập Google bị huỷ');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    final user = result.user!;

    // Tạo profile nếu là lần đầu đăng nhập.
    if (result.additionalUserInfo?.isNewUser ?? false) {
      await _userRepo.saveUser(AppUser(
        uid: user.uid,
        name: user.displayName ?? 'Người dùng',
        email: user.email ?? '',
        avatarUrl: user.photoURL,
        qrImageUrl: null, // sẽ yêu cầu upload ở onboarding
      ));
    }

    return user;
  }

  /// Đăng ký bằng email/password.
  /// Tạo profile Firestore ngay sau khi đăng ký thành công.
  Future<User> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = result.user!;

    await _userRepo.saveUser(AppUser(
      uid: user.uid,
      name: name,
      email: email,
      avatarUrl: null,
      qrImageUrl: null,
    ));

    return user;
  }

  /// Đăng nhập bằng email/password.
  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return result.user!;
  }

  /// Đăng xuất khỏi cả Firebase và Google.
  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(authProvider),
    ref.watch(userRepositoryProvider),
  );
});
